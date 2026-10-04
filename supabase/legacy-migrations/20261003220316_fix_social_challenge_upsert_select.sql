-- Allow a challenge creator to read the row directly during
-- PostgREST INSERT/UPSERT ... RETURNING.
--
-- The previous SELECT policy delegated all visibility checks to
-- private.can_view_challenge(id). During the same INSERT statement,
-- that helper cannot reliably see the newly inserted row, causing
-- Supabase Swift's default return=representation upsert to fail with
-- SQLSTATE 42501 even though the INSERT creator check passes.

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
