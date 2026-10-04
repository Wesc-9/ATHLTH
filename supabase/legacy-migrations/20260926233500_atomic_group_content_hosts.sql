create or replace function public.set_community_group_content_hosts(
  p_group_id uuid,
  p_content_type text,
  p_content_id uuid,
  p_user_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  candidate uuid;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if p_content_type not in ('event','challenge') then
    raise exception 'Invalid content type';
  end if;

  if not private.community_group_content_exists(
    p_group_id,
    p_content_type,
    p_content_id
  ) then
    raise exception 'Group content not found';
  end if;

  if not private.can_manage_community_group_content(
    p_group_id,
    p_content_type,
    p_content_id,
    actor
  ) then
    raise exception 'Content management permission required';
  end if;

  delete from public.community_group_content_hosts
  where group_id = p_group_id
    and content_type = p_content_type
    and content_id = p_content_id;

  foreach candidate in array coalesce(p_user_ids, array[]::uuid[])
  loop
    if candidate = actor
       or private.is_community_group_member(
         p_group_id,
         candidate
       ) then
      insert into public.community_group_content_hosts(
        group_id,
        content_type,
        content_id,
        user_id
      )
      values (
        p_group_id,
        p_content_type,
        p_content_id,
        candidate
      )
      on conflict do nothing;
    else
      raise exception 'Co-host must be a group member';
    end if;
  end loop;
end;
$$;

grant execute on function public.set_community_group_content_hosts(
  uuid,text,uuid,uuid[]
) to authenticated;
revoke all on function public.set_community_group_content_hosts(
  uuid,text,uuid,uuid[]
) from public, anon;
