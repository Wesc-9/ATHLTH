create index if not exists live_workout_locations_user_idx
  on public.live_workout_locations(user_id);

revoke execute on function public.prune_stale_live_workout_state()
  from authenticated;
grant execute on function public.prune_stale_live_workout_state()
  to service_role;
