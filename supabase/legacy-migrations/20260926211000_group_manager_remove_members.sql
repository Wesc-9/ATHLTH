-- Owner/Admin may remove non-owner group members.
drop policy if exists group_members_remove_managers
  on public.community_group_members;

create policy group_members_remove_managers
  on public.community_group_members
  for delete
  to authenticated
  using (
    role <> 'owner'
    and private.can_manage_community_group(group_id)
  );
