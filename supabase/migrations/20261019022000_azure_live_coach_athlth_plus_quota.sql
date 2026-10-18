-- Azure Speech F0 live messages are ATHLTH+-only and share the existing
-- global 400k character/month fail-closed reservation with voice previews.
-- Dedicated user-level limits keep strength/rest coach useful without
-- consuming the unrelated Groq AI request quota.
create table if not exists private.athlth_azure_tts_daily_use (
  user_id uuid not null,
  day_start date not null,
  minute_start timestamptz not null,
  minute_calls integer not null default 0 check (minute_calls >= 0),
  day_calls integer not null default 0 check (day_calls >= 0),
  primary key (user_id, day_start)
);
revoke all on private.athlth_azure_tts_daily_use from public, anon, authenticated;
grant select, insert, update on private.athlth_azure_tts_daily_use to service_role;

create or replace function public.reserve_athlth_azure_tts_live(
  p_user_id uuid,
  p_characters integer
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  now_utc timestamptz := clock_timestamp();
  today_utc date := (clock_timestamp() at time zone 'UTC')::date;
  month_utc date := date_trunc('month', clock_timestamp() at time zone 'UTC')::date;
  minute_utc timestamptz := date_trunc('minute', clock_timestamp());
  activity private.athlth_azure_tts_daily_use%rowtype;
  minute_count integer;
  reserved integer;
begin
  if p_user_id is null or p_characters < 1 or p_characters > 220 then
    return false;
  end if;

  insert into private.athlth_azure_tts_daily_use
    (user_id, day_start, minute_start, minute_calls, day_calls)
  values (p_user_id, today_utc, minute_utc, 0, 0)
  on conflict do nothing;

  select * into activity
  from private.athlth_azure_tts_daily_use
  where user_id = p_user_id and day_start = today_utc
  for update;

  if not found then return false; end if;

  minute_count := case
    when activity.minute_start = minute_utc then activity.minute_calls
    else 0
  end;
  -- Per-subscriber fair-use budget: up to 4 calls/minute, 100/day.
  -- The global F0 allowance remains the authoritative price cap.
  if minute_count >= 4 or activity.day_calls >= 100 then
    return false;
  end if;

  insert into private.athlth_azure_tts_monthly_usage
    (month_start, used_characters, requests)
  values (month_utc, p_characters, 1)
  on conflict (month_start) do update
    set used_characters = private.athlth_azure_tts_monthly_usage.used_characters
                          + excluded.used_characters,
        requests = private.athlth_azure_tts_monthly_usage.requests + 1
  where private.athlth_azure_tts_monthly_usage.used_characters
        + excluded.used_characters <= 400000
  returning used_characters into reserved;

  if reserved is null then return false; end if;

  update private.athlth_azure_tts_daily_use
  set minute_start = minute_utc,
      minute_calls = minute_count + 1,
      day_calls = activity.day_calls + 1
  where user_id = p_user_id and day_start = today_utc;

  return true;
end;
$$;

revoke all on function public.reserve_athlth_azure_tts_live(uuid, integer)
from public, anon, authenticated;
grant execute on function public.reserve_athlth_azure_tts_live(uuid, integer)
to service_role;
