drop policy if exists "No direct client access to award unlocks"
  on public.athlth_award_unlocks;
create policy "No direct client access to award unlocks"
  on public.athlth_award_unlocks
  as restrictive
  for all
  to anon, authenticated
  using (false)
  with check (false);

drop policy if exists "No direct client access to award preferences"
  on public.user_award_preferences;
create policy "No direct client access to award preferences"
  on public.user_award_preferences
  as restrictive
  for all
  to anon, authenticated
  using (false)
  with check (false);
