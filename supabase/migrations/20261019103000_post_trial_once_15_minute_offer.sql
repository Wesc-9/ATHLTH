-- ATHLTH+ one-time post-trial claim window. Nothing is shown until real,
-- unused App Store Connect offer codes have been imported by an admin.
-- A 15-minute window starts ONLY on the user's first eligible app opening.
-- The claim deadline is enforced by the server, never by the device clock.
create schema if not exists private;

create table if not exists private.athlth_post_trial_offer_codes (
    code text primary key,
    product_id text not null default 'com.wesc9.athlth.paid.yearly',
    apple_expires_at timestamptz,
    assigned_user_id uuid unique,
    assigned_at timestamptz,
    check (length(code) between 5 and 80),
    check (product_id in (
      'com.wesc9.athlth.paid.yearly',
      'com.wesc9.athlth.paid.monthly'
    ))
);

create table if not exists private.athlth_post_trial_offer_windows (
    user_id uuid primary key,
    presented_at timestamptz not null,
    claim_deadline timestamptz not null,
    code text unique references private.athlth_post_trial_offer_codes(code),
    claimed_at timestamptz,
    check (claim_deadline = presented_at + interval '15 minutes')
);

revoke all on private.athlth_post_trial_offer_codes from public, anon, authenticated;
revoke all on private.athlth_post_trial_offer_windows from public, anon, authenticated;
grant select, insert, update on private.athlth_post_trial_offer_codes to service_role;
grant select, insert, update on private.athlth_post_trial_offer_windows to service_role;

create or replace function public.start_athlth_post_trial_offer(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  entitlement public.subscription_entitlements%rowtype;
  current_window private.athlth_post_trial_offer_windows%rowtype;
  offered_code text;
  deadline timestamptz;
  instant timestamptz := clock_timestamp();
begin
  if p_user_id is null then return '{"status":"unavailable"}'::jsonb; end if;

  -- Lock this entitlement so concurrent iPhone/iPad sessions cannot both
  -- present an offer (and reserve multiple codes).
  select * into entitlement
  from public.subscription_entitlements
  where user_id = p_user_id for update;
  if not found
     or entitlement.tier <> 'athlth_plus'
     or entitlement.status not in ('expired', 'trialing')
     or entitlement.trial_ends_at is null
     or entitlement.trial_ends_at > instant
     or entitlement.app_store_original_transaction_id is not null
     or entitlement.current_period_ends_at is not null
  then
    return '{"status":"unavailable"}'::jsonb;
  end if;

  if exists (
    select 1 from private.athlth_post_trial_offer_windows
    where user_id = p_user_id
  ) then
    -- A second launch NEVER presents the same campaign again, even if
    -- the original 15-minute claim window has not elapsed.
    return '{"status":"already_presented"}'::jsonb;
  end if;

  -- Return codes from expired, unclaimed windows to the inventory. Their
  -- original users remain recorded and cannot receive a second popup.
  update private.athlth_post_trial_offer_codes c
  set assigned_user_id = null, assigned_at = null
  from private.athlth_post_trial_offer_windows w
  where c.code = w.code and c.assigned_user_id = w.user_id
    and w.claimed_at is null and w.claim_deadline <= instant;

  update private.athlth_post_trial_offer_windows
  set code = null
  where claimed_at is null and claim_deadline <= instant;

  select code into offered_code
  from private.athlth_post_trial_offer_codes
  where assigned_user_id is null
    and (apple_expires_at is null or apple_expires_at > instant + interval '1 hour')
  order by apple_expires_at nulls last, code
  for update skip locked
  limit 1;
  if offered_code is null then return '{"status":"unavailable"}'::jsonb; end if;

  deadline := instant + interval '15 minutes';
  insert into private.athlth_post_trial_offer_windows
    (user_id, presented_at, claim_deadline, code)
  values (p_user_id, instant, deadline, offered_code);

  update private.athlth_post_trial_offer_codes
  set assigned_user_id = p_user_id, assigned_at = instant
  where code = offered_code;

  return jsonb_build_object(
    'status', 'new',
    'expiresAt', to_char(deadline at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );
end;
$$;

create or replace function public.claim_athlth_post_trial_offer(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  window_row private.athlth_post_trial_offer_windows%rowtype;
  instant timestamptz := clock_timestamp();
  code_value text;
begin
  if p_user_id is null then return '{"status":"unavailable"}'::jsonb; end if;

  select * into window_row
  from private.athlth_post_trial_offer_windows
  where user_id = p_user_id for update;

  if not found then return '{"status":"unavailable"}'::jsonb; end if;

  if window_row.claim_deadline <= instant
  then return '{"status":"expired"}'::jsonb; end if;

  if window_row.claimed_at is not null or window_row.code is null
  then return '{"status":"already_claimed"}'::jsonb; end if;

  -- Recheck the user's account just before revealing the real Apple code.
  if not exists (
    select 1 from public.subscription_entitlements e
    where e.user_id = p_user_id and e.tier = 'athlth_plus'
      and e.status in ('expired', 'trialing')
      and e.trial_ends_at <= instant
      and e.app_store_original_transaction_id is null
      and e.current_period_ends_at is null
  ) then return '{"status":"unavailable"}'::jsonb; end if;

  select code into code_value
  from private.athlth_post_trial_offer_codes
  where code = window_row.code
    and assigned_user_id = p_user_id
    and (apple_expires_at is null or apple_expires_at > instant)
  for update;
  if code_value is null then return '{"status":"unavailable"}'::jsonb; end if;

  update private.athlth_post_trial_offer_windows
  set claimed_at = instant
  where user_id = p_user_id;

  return jsonb_build_object('status', 'claimed', 'code', code_value);
end;
$$;

revoke all on function public.start_athlth_post_trial_offer(uuid)
  from public, anon, authenticated;
revoke all on function public.claim_athlth_post_trial_offer(uuid)
  from public, anon, authenticated;
grant execute on function public.start_athlth_post_trial_offer(uuid)
  to service_role;
grant execute on function public.claim_athlth_post_trial_offer(uuid)
  to service_role;
