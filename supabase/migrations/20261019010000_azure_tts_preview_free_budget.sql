-- Hard cap Azure Speech F0 previews below its monthly free character allowance.
create schema if not exists private;
create table if not exists private.athlth_azure_tts_monthly_usage (
  month_start date primary key,
  used_characters integer not null default 0 check (used_characters >= 0),
  requests integer not null default 0 check (requests >= 0)
);
revoke all on private.athlth_azure_tts_monthly_usage from public, anon, authenticated;
grant select, insert, update on private.athlth_azure_tts_monthly_usage to service_role;
create or replace function public.reserve_athlth_azure_tts_preview(
  p_characters integer
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_month date := date_trunc('month', clock_timestamp() at time zone 'UTC')::date;
  reserved integer;
begin
  if p_characters < 1 or p_characters > 300 then return false; end if;
  insert into private.athlth_azure_tts_monthly_usage
    (month_start, used_characters, requests)
  values (current_month, p_characters, 1)
  on conflict (month_start) do update
    set used_characters = private.athlth_azure_tts_monthly_usage.used_characters
                          + excluded.used_characters,
        requests = private.athlth_azure_tts_monthly_usage.requests + 1
  where private.athlth_azure_tts_monthly_usage.used_characters
         + excluded.used_characters <= 400000
  returning used_characters into reserved;
  return reserved is not null;
end;
$$;
revoke all on function public.reserve_athlth_azure_tts_preview(integer)
  from public, anon, authenticated;
grant execute on function public.reserve_athlth_azure_tts_preview(integer)
  to service_role;
