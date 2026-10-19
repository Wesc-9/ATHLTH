-- Allow an athlete to remove their own chosen training focus entirely.
-- Other users cannot delete someone else's profile focus.
drop policy if exists social_training_focus_delete_own
  on public.social_training_focus;

create policy social_training_focus_delete_own
  on public.social_training_focus
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);
