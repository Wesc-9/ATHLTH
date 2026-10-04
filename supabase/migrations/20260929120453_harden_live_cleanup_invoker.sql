-- Restrict client-triggered cleanup to the caller's own stale state.
-- SECURITY INVOKER keeps normal RLS/ownership policies in force.

create or replace function public.cleanup_expired_live_workout_state()
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  delete from public.live_workout_locations
  where user_id = (select auth.uid())
    and expires_at <= now();

  update public.live_workout_sessions
  set status = 'completed',
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where owner_id = (select auth.uid())
    and status in ('active','paused')
    and started_at < now() - interval '12 hours';
end;
$$;

revoke all on function public.cleanup_expired_live_workout_state()
  from public, anon;
grant execute on function public.cleanup_expired_live_workout_state()
  to authenticated;
