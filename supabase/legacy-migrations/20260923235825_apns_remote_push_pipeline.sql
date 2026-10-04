create extension if not exists pg_net;

alter table public.social_inbox_events
  add column if not exists push_notified_at timestamptz;

create or replace function public.register_notification_device(
  p_device_id text,
  p_platform text,
  p_app_bundle_id text,
  p_apns_environment text,
  p_apns_token text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
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
    last_seen_at
  )
  values (
    actor,
    p_device_id,
    p_platform,
    p_app_bundle_id,
    p_apns_environment,
    p_apns_token,
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
    last_seen_at = now(),
    updated_at = now();
end;
$$;

revoke all on function public.register_notification_device(
  text, text, text, text, text
) from public, anon;
grant execute on function public.register_notification_device(
  text, text, text, text, text
) to authenticated;

create or replace function public.unregister_notification_device(
  p_device_id text,
  p_app_bundle_id text,
  p_apns_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  delete from public.notification_devices d
  where d.user_id = actor
    and d.device_id = p_device_id
    and d.app_bundle_id = p_app_bundle_id
    and d.apns_environment = p_apns_environment;
end;
$$;

revoke all on function public.unregister_notification_device(
  text, text, text
) from public, anon;
grant execute on function public.unregister_notification_device(
  text, text, text
) to authenticated;

create or replace function private.enqueue_social_inbox_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://hnkybbzxffvyhzrstqdo.supabase.co/functions/v1/send-apns-push',
    body := jsonb_build_object('event_id', new.id),
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    raise warning 'ATHLTH push enqueue failed for event %: %', new.id, sqlerrm;
    return new;
end;
$$;

revoke all on function private.enqueue_social_inbox_push()
from public, anon, authenticated;

drop trigger if exists social_inbox_events_push_after_insert
on public.social_inbox_events;

create trigger social_inbox_events_push_after_insert
after insert on public.social_inbox_events
for each row execute function private.enqueue_social_inbox_push();
