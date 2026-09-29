-- Add optional live heart-rate context and a safe, caller-triggered cleanup path.
-- Live GPS remains one mutable latest row per participant; the UI-only trail is
-- reconstructed in memory and is never persisted.

alter table public.live_workout_locations
  add column if not exists heart_rate_bpm double precision
    check (
      heart_rate_bpm is null
      or heart_rate_bpm between 20 and 260
    );

create or replace function public.cleanup_expired_live_workout_state()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  delete from public.live_workout_locations
  where expires_at <= now();

  update public.live_workout_sessions
  set status = 'completed',
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where status in ('active','paused')
    and started_at < now() - interval '12 hours';
end;
$$;

revoke all on function public.cleanup_expired_live_workout_state()
  from public, anon;
grant execute on function public.cleanup_expired_live_workout_state()
  to authenticated;
