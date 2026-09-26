-- Group v2 roles and permissions.
-- Keep the creator represented internally as owner, while the UI exposes
-- Admin / Contributor / Member. Contributors can publish group updates only.

alter table public.community_group_members
  drop constraint if exists community_group_members_role_check;

alter table public.community_group_members
  add constraint community_group_members_role_check
  check (role in ('owner', 'admin', 'contributor', 'member'));

create or replace function private.can_publish_community_group_update(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    exists (
      select 1
      from public.community_groups g
      where g.id = p_group_id
        and g.creator_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.community_group_members gm
      where gm.group_id = p_group_id
        and gm.user_id = (select auth.uid())
        and gm.role in ('owner', 'admin', 'contributor')
    );
$$;

grant execute on function private.can_publish_community_group_update(uuid)
  to authenticated;

drop policy if exists group_members_update_owner
  on public.community_group_members;
drop policy if exists group_members_update_managers
  on public.community_group_members;

create policy group_members_update_managers
  on public.community_group_members
  for update
  to authenticated
  using (
    role <> 'owner'
    and private.can_manage_community_group(group_id)
  )
  with check (
    role in ('admin', 'contributor', 'member')
    and private.can_manage_community_group(group_id)
  );

drop policy if exists group_announcements_insert_managers
  on public.community_group_announcements;
drop policy if exists group_announcements_insert_publishers
  on public.community_group_announcements;

create policy group_announcements_insert_publishers
  on public.community_group_announcements
  for insert
  to authenticated
  with check (
    author_id = (select auth.uid())
    and private.can_publish_community_group_update(group_id)
  );

drop policy if exists groups_delete_creator
  on public.community_groups;
drop policy if exists groups_delete_managers
  on public.community_groups;

create policy groups_delete_managers
  on public.community_groups
  for delete
  to authenticated
  using (private.can_manage_community_group(id));
