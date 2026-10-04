-- Fix Club content RLS helper execution.
-- The event/challenge SELECT and UPDATE policies call this helper as the
-- authenticated role. Keep the existing signature stable, bind p_user_id to
-- auth.uid() to prevent caller spoofing, and allow authenticated policy use.

create or replace function private.can_manage_community_group_content(
  p_group_id uuid,
  p_content_type text,
  p_content_id uuid,
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
    and (
      private.can_manage_community_group(p_group_id)
      or case
        when p_content_type = 'event' then exists (
          select 1
          from public.community_group_events e
          where e.id = p_content_id
            and e.group_id = p_group_id
            and e.creator_id = p_user_id
        )
        when p_content_type = 'challenge' then exists (
          select 1
          from public.community_group_challenges c
          where c.id = p_content_id
            and c.group_id = p_group_id
            and c.creator_id = p_user_id
        )
        else false
      end
      or exists (
        select 1
        from public.community_group_content_hosts h
        where h.group_id = p_group_id
          and h.content_type = p_content_type
          and h.content_id = p_content_id
          and h.user_id = p_user_id
      )
    );
$$;

revoke all on function private.can_manage_community_group_content(
  uuid,text,uuid,uuid
) from public, anon;

grant execute on function private.can_manage_community_group_content(
  uuid,text,uuid,uuid
) to authenticated;
