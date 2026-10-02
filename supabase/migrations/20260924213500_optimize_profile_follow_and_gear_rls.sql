-- ATHLTH 1.3.8: optimize profile follow and gear RLS auth checks

drop policy if exists "users can follow from their own account" on public.profile_follows;
create policy "users can follow from their own account"
  on public.profile_follows
  for insert
  to authenticated
  with check ((select auth.uid()) = follower_id and follower_id <> following_id);

drop policy if exists "users can unfollow from their own account" on public.profile_follows;
create policy "users can unfollow from their own account"
  on public.profile_follows
  for delete
  to authenticated
  using ((select auth.uid()) = follower_id);

drop policy if exists "users can add their own profile gear" on public.profile_gear;
create policy "users can add their own profile gear"
  on public.profile_gear
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "users can update their own profile gear" on public.profile_gear;
create policy "users can update their own profile gear"
  on public.profile_gear
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "users can delete their own profile gear" on public.profile_gear;
create policy "users can delete their own profile gear"
  on public.profile_gear
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);
