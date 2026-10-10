-- Restrictive policy composes with existing permissive DELETE policies.
-- An administrator cannot remove another administrator from a Club.
-- Own membership can still be left voluntarily (except owner).
DROP POLICY IF EXISTS community_group_admin_removal_guard ON public.community_group_members;
CREATE POLICY community_group_admin_removal_guard
  ON public.community_group_members
  AS RESTRICTIVE
  FOR DELETE
  TO authenticated
  USING (
    role <> 'admin'
    OR user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.community_groups g
      WHERE g.id = community_group_members.group_id
        AND g.creator_id = (SELECT auth.uid())
    )
  );
