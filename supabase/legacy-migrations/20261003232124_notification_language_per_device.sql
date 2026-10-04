-- ATHLTH 1.5.9: keep APNs language aligned with the language selected in-app.
-- The existing five-argument registration RPC remains available so older
-- installed builds keep registering devices. New builds use the six-argument
-- overload and persist the selected notification language per device.

alter table public.notification_devices
  add column if not exists language_code text not null default 'en';

alter table public.notification_devices
  drop constraint if exists notification_devices_language_code_check;

alter table public.notification_devices
  add constraint notification_devices_language_code_check
  check (language_code in ('en', 'nb'));

create or replace function public.register_notification_device(
  p_device_id text,
  p_platform text,
  p_app_bundle_id text,
  p_apns_environment text,
  p_apns_token text,
  p_language_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  resolved_language text := lower(coalesce(nullif(btrim(p_language_code), ''), 'en'));
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if nullif(btrim(p_device_id), '') is null
     or char_length(p_device_id) > 200 then
    raise exception 'Invalid device identifier';
  end if;

  if p_platform <> 'ios' then
    raise exception 'Unsupported notification platform';
  end if;

  if p_apns_environment not in ('sandbox', 'production') then
    raise exception 'Invalid APNs environment';
  end if;

  if nullif(btrim(p_app_bundle_id), '') is null
     or char_length(p_app_bundle_id) > 200 then
    raise exception 'Invalid app bundle identifier';
  end if;

  if nullif(btrim(p_apns_token), '') is null
     or char_length(p_apns_token) > 512 then
    raise exception 'Invalid APNs token';
  end if;

  if resolved_language not in ('en', 'nb') then
    resolved_language := 'en';
  end if;

  delete from public.notification_devices d
  where d.app_bundle_id = p_app_bundle_id
    and d.apns_environment = p_apns_environment
    and (
      d.device_id = p_device_id
      or d.apns_token = p_apns_token
    )
    and d.user_id <> actor;

  insert into public.notification_devices (
    user_id,
    device_id,
    platform,
    app_bundle_id,
    apns_environment,
    apns_token,
    language_code,
    last_seen_at
  )
  values (
    actor,
    p_device_id,
    p_platform,
    p_app_bundle_id,
    p_apns_environment,
    p_apns_token,
    resolved_language,
    now()
  )
  on conflict (
    user_id,
    device_id,
    app_bundle_id,
    apns_environment
  )
  do update set
    platform = excluded.platform,
    apns_token = excluded.apns_token,
    language_code = excluded.language_code,
    last_seen_at = now(),
    updated_at = now();
end;
$$;

revoke all on function public.register_notification_device(
  text, text, text, text, text, text
) from public, anon;

grant execute on function public.register_notification_device(
  text, text, text, text, text, text
) to authenticated;
