drop policy if exists social_challenges_select_allowed
         on public.social_challenges;

         create policy social_challenges_select_allowed
         on public.social_challenges
         for select
         to authenticated
         using (
           ((select auth.uid()) = creator_id)
           or private.can_view_challenge(id)
         );
