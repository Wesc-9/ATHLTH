-- Extend the admin directory without exposing the Auth schema or breaking v3 clients.
create or replace function private.athlth_admin_directory_v4(
    p_search text default '',
    p_sort text default 'joined_newest',
    p_limit integer default 50,
    p_offset integer default 0
) returns table(
    user_id uuid, username text, display_name text, avatar_url text,
    account_role text, subscription_tier text, subscription_status text,
    account_state text, joined_at timestamptz, total_count bigint,
    admin_plus_grant_active boolean, admin_plus_grant_expires_at timestamptz,
    last_sign_in_at timestamptz
) language plpgsql stable security definer set search_path = ''
as $$
begin
    if (select auth.uid()) is null or not (select private.is_app_admin()) then
        raise exception 'Access denied' using errcode = '42501';
    end if;
    return query
    select d.user_id, d.username, d.display_name, d.avatar_url,
        d.account_role, d.subscription_tier, d.subscription_status,
        d.account_state, d.joined_at, d.total_count,
        d.admin_plus_grant_active, d.admin_plus_grant_expires_at,
        u.last_sign_in_at
    from private.athlth_admin_directory_v3(p_search,p_sort,p_limit,p_offset)
         with ordinality d
    join auth.users u on u.id = d.user_id and u.deleted_at is null
    order by d.ordinality;
end;
$$;
revoke all on function private.athlth_admin_directory_v4(text,text,integer,integer) from public,anon;
grant execute on function private.athlth_admin_directory_v4(text,text,integer,integer) to authenticated;

create or replace function public.athlth_admin_directory_v4(
    p_search text default '',
    p_sort text default 'joined_newest',
    p_limit integer default 50,
    p_offset integer default 0
) returns table(
    user_id uuid, username text, display_name text, avatar_url text,
    account_role text, subscription_tier text, subscription_status text,
    account_state text, joined_at timestamptz, total_count bigint,
    admin_plus_grant_active boolean, admin_plus_grant_expires_at timestamptz,
    last_sign_in_at timestamptz
) language sql stable security invoker set search_path = ''
as $$
    select * from private.athlth_admin_directory_v4(p_search,p_sort,p_limit,p_offset);
$$;
revoke all on function public.athlth_admin_directory_v4(text,text,integer,integer) from public,anon;
grant execute on function public.athlth_admin_directory_v4(text,text,integer,integer) to authenticated;
