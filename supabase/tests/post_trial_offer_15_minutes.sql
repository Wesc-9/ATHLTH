-- Run ONLY against disposable local Supabase in CI. Every fixture rolls back.
begin;

insert into auth.users(id)
values
 ('f15f0000-0000-4000-8000-000000000001'),
 ('f15f0000-0000-4000-8000-000000000002'),
 ('f15f0000-0000-4000-8000-000000000003');

insert into public.subscription_entitlements
 (user_id,tier,status,source,trial_started_at,trial_ends_at)
values
 ('f15f0000-0000-4000-8000-000000000001','athlth_plus','expired','athlth_trial',
   clock_timestamp() - interval '10 days',clock_timestamp() - interval '3 days'),
 ('f15f0000-0000-4000-8000-000000000002','athlth_plus','expired','athlth_trial',
   clock_timestamp() - interval '9 days',clock_timestamp() - interval '2 days'),
 ('f15f0000-0000-4000-8000-000000000003','athlth_plus','trialing','athlth_trial',
   clock_timestamp() - interval '1 day',clock_timestamp() + interval '6 days')
on conflict (user_id) do update
  set tier=excluded.tier,status=excluded.status,source=excluded.source,
      trial_started_at=excluded.trial_started_at,
      trial_ends_at=excluded.trial_ends_at;

insert into private.athlth_post_trial_offer_codes(code,apple_expires_at)
values
 ('ATHLTH-TEST-CODE-1',clock_timestamp() + interval '5 days'),
 ('ATHLTH-TEST-CODE-2',clock_timestamp() + interval '5 days');

do $$
declare
  expired_one uuid := 'f15f0000-0000-4000-8000-000000000001';
  expired_two uuid := 'f15f0000-0000-4000-8000-000000000002';
  current_trial uuid := 'f15f0000-0000-4000-8000-000000000003';
  result jsonb;
  count_reserved integer;
begin
  result := public.start_athlth_post_trial_offer(current_trial);
  if result->>'status' <> 'unavailable' then
    raise exception 'Unexpired trial incorrectly received a limited offer';
  end if;

  result := public.start_athlth_post_trial_offer(expired_one);
  if result->>'status' <> 'new' then
    raise exception 'First eligible opening failed to create offer';
  end if;
  if (result->>'expiresAt')::timestamptz > clock_timestamp() + interval '15 minutes'
     or (result->>'expiresAt')::timestamptz < clock_timestamp() + interval '14 minutes'
  then raise exception 'Wrong 15-minute deadline'; end if;

  result := public.start_athlth_post_trial_offer(expired_one);
  if result->>'status' <> 'already_presented' then
    raise exception 'Second opening incorrectly repeated offer';
  end if;

  result := public.claim_athlth_post_trial_offer(expired_one);
  if result->>'status' <> 'claimed'
     or result->>'code' <> 'ATHLTH-TEST-CODE-1' then
    raise exception 'First eligible claim was rejected or leaked wrong code';
  end if;

  result := public.claim_athlth_post_trial_offer(expired_one);
  if result->>'status' <> 'already_claimed' then
    raise exception 'Same user could retrieve one-time code a second time';
  end if;

  result := public.start_athlth_post_trial_offer(expired_two);
  if result->>'status' <> 'new' then
    raise exception 'Second user must get an independent offer';
  end if;

  -- Preserve the exact CHECK expression with a single shared timestamp.
  update private.athlth_post_trial_offer_windows
  set presented_at = claim_deadline - interval '16 minutes',
      claim_deadline = claim_deadline - interval '1 minute'
  where user_id = expired_two;

  result := public.claim_athlth_post_trial_offer(expired_two);
  if result->>'status' <> 'expired' then
    raise exception 'Expired window allowed redemption';
  end if;

  result := public.start_athlth_post_trial_offer(expired_two);
  if result->>'status' <> 'already_presented' then
    raise exception 'Expired window was allowed to restart';
  end if;

  select count(*) into count_reserved
  from private.athlth_post_trial_offer_windows;
  if count_reserved <> 2 then
    raise exception 'Expected only two permanent one-shot offers, got %',
      count_reserved;
  end if;

  if has_function_privilege('anon','public.start_athlth_post_trial_offer(uuid)','EXECUTE')
     or has_function_privilege('authenticated','public.claim_athlth_post_trial_offer(uuid)','EXECUTE')
  then
    raise exception 'Unsafe direct RPC access to privileged offer gate';
  end if;
end $$;

rollback;
