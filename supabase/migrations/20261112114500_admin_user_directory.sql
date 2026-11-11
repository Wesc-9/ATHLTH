-- A minimal owner/admin-only directory for developer tools.
-- No email, HealthKit, location, messages, workouts or private profile fields.
-- Strict paging, server-side role check and no service-role key in the app.

create or replace function private.athlth_admin_directory(
    p_search text default '',
    p_limit integer default 50,
    p_offset integer default 0
)
returns table(
    user_id uuid,
    username text,
    display_name text,
    account_role text,
    subscription_tier text,
    joined_at timestamptz,
    total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if (select auth.uid()) is null or not (select private.is_app_admin()) then
        raise exception 'Access denied' using errcode = '42501';
    end if;
    return query
    select p.id, p.username::text, p.display_name,
           coalesce(r.role, 'user'),
           coalesce(e.tier, 'free'),
           p.created_at,
           count(*) over()
    from public.profiles p
    left join public.account_roles r on r.user_id = p.id
    left join public.subscription_entitlements e on e.user_id = p.id
    where length(trim(coalesce(p_search,''))) = 0
       or position(
           lower(left(trim(p_search), 80)) in
           lower(coalesce(p.username::text,'') || ' ' || coalesce(p.display_name,''))
       ) > 0
    order by p.created_at desc, p.id
    limit least(greatest(coalesce(p_limit, 50), 1), 100)
    offset least(greatest(coalesce(p_offset, 0), 0), 100000);
end;
$$;

revoke all on function private.athlth_admin_directory(text, integer, integer) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.athlth_admin_directory(text, integer, integer) to authenticated;

-- Exposed wrapper is SECURITY INVOKER, not SECURITY DEFINER.
create or replace function public.athlth_admin_directory(
    p_search text default '',
    p_limit integer default 50,
    p_offset integer default 0
)
returns table(
    user_id uuid,
    username text,
    display_name text,
    account_role text,
    subscription_tier text,
    joined_at timestamptz,
    total_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
    select * from private.athlth_admin_directory(p_search, p_limit, p_offset);
$$;
revoke all on function public.athlth_admin_directory(text, integer, integer) from public, anon;
grant execute on function public.athlth_admin_directory(text, integer, integer) to authenticated;
