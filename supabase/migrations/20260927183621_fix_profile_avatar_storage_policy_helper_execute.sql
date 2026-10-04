create or replace function private.can_create_community_group_content(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    (select auth.uid()) is not null
    and p_user_id = (select auth.uid())
    and exists (
      select 1
      from public.community_groups g
      left join public.community_group_members gm
        on gm.group_id = g.id
       and gm.user_id = p_user_id
      where g.id = p_group_id
        and (
          g.creator_id = p_user_id
          or gm.role in ('owner', 'admin', 'contributor')
          or (
            gm.role = 'member'
            and g.members_can_create_content = true
          )
        )
    );
$$;

revoke all on function private.can_create_community_group_content(uuid, uuid)
  from public, anon, authenticated;

grant execute on function private.can_create_community_group_content(uuid, uuid)
  to authenticated;
