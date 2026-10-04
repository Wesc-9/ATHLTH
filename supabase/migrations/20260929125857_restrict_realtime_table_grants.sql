revoke all on table public.social_online_presence from anon, authenticated;
revoke all on table public.live_workout_sessions from anon, authenticated;
revoke all on table public.live_workout_locations from anon, authenticated;

grant select, insert, update
  on table public.social_online_presence
  to authenticated;

grant select, insert, update
  on table public.live_workout_sessions
  to authenticated;

grant select, insert, update, delete
  on table public.live_workout_locations
  to authenticated;
