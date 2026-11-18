-- ATHLTH 2.2.5: owner-managed complimentary Plus grants.
-- Keep manual grants separate from StoreKit-backed subscription_entitlements.
-- No health, workout, message or payment data is exposed in the admin directory.

create table if not exists public.athlth_admin_plus_grants (
    user_id uuid primary key references auth.users(id) on delete cascade,
    granted_by uuid not null references auth.users(id),
    granted_at timestamptz not null default now(),
    expires_at timestamptz,
    revoked_at timestamptz,
    revoked_by uuid references auth.users(id),
    constraint athlth_admin_plus_grant_valid_expiry
        check (expires_at is null or expires_at > granted_at)
);
alter table public.athlth_admin_plus_grants enable row level security;
revoke all on table public.athlth_admin_plus_grants from public, anon, authenticated;
grant select on table public.athlth_admin_plus_grants to authenticated;
create policy athlth_admin_plus_grant_read_self
    on public.athlth_admin_plus_grants for select to authenticated
    using (user_id = (select auth.uid()));

create or replace function private.athlth_admin_manage_plus_grant(
    p_target uuid,
    p_action text,
    p_duration_days integer,
    p_reason text,
    p_confirm_username text
) returns boolean language plpgsql volatile security definer set search_path = ''
as $$
declare
    v_actor uuid := (select auth.uid());
    v_role text;
    v_username text;
    v_reason text := trim(coalesce(p_reason, ''));
    v_expiry timestamptz;
    v_rows integer;
begin
    if v_actor is null or not exists (
        select 1 from public.account_roles
        where user_id = v_actor and role = 'owner'
    ) then
        raise exception 'Owner permission required' using errcode = '42501';
    end if;
    if p_target is null or p_target = v_actor
       or p_action not in ('grant', 'revoke')
       or length(v_reason) not between 10 and 500
       or (p_action = 'grant' and p_duration_days is not null
           and p_duration_days not in (7, 30, 90, 365))
       or (p_action = 'revoke' and p_duration_days is not null) then
        raise exception 'Invalid Plus-grant request' using errcode = '22023';
    end if;
    select r.role, p.username::text into v_role, v_username
      from public.profiles p
      join public.account_roles r on r.user_id = p.id
      join auth.users u on u.id = p.id and u.deleted_at is null
      where p.id = p_target
      for update of p;
    if not found or v_role = 'owner'
       or v_username is null
       or lower(v_username) <> lower(trim(coalesce(p_confirm_username, ''))) then
        raise exception 'Target account unavailable or confirmation mismatch'
            using errcode = '42501';
    end if;

    if p_action = 'grant' then
        v_expiry := case when p_duration_days is null then null
             else clock_timestamp() + make_interval(days => p_duration_days) end;
        insert into public.athlth_admin_plus_grants
            (user_id, granted_by, granted_at, expires_at, revoked_at, revoked_by)
        values (p_target, v_actor, clock_timestamp(), v_expiry, null, null)
        on conflict (user_id) do update set
            granted_by = excluded.granted_by,
            granted_at = excluded.granted_at,
            expires_at = excluded.expires_at,
            revoked_at = null,
            revoked_by = null;
    else
        update public.athlth_admin_plus_grants
          set revoked_at = clock_timestamp(), revoked_by = v_actor
          where user_id = p_target and revoked_at is null
            and (expires_at is null or expires_at > clock_timestamp());
        get diagnostics v_rows = row_count;
        if v_rows <> 1 then
            raise exception 'No active manual Plus grant to revoke' using errcode = '22023';
        end if;
    end if;

    insert into public.athlth_admin_account_audit
        (actor_id, target_id, action, reason, metadata)
    values (
        v_actor, p_target,
        case when p_action = 'grant' then 'athlth_plus_granted'
             else 'athlth_plus_revoked' end,
        v_reason,
        jsonb_build_object('duration_days', p_duration_days,
                           'expires_at', v_expiry,
                           'origin', 'owner_grant')
    );
    return true;
end;
$$;
revoke all on function private.athlth_admin_manage_plus_grant(uuid,text,integer,text,text)
    from public, anon;
grant execute on function private.athlth_admin_manage_plus_grant(uuid,text,integer,text,text)
    to authenticated;

create or replace function public.athlth_admin_manage_plus_grant(
    p_target uuid,
    p_action text,
    p_duration_days integer,
    p_reason text,
    p_confirm_username text
) returns boolean language sql volatile security invoker set search_path = ''
as $$
    select private.athlth_admin_manage_plus_grant(
        p_target, p_action, p_duration_days, p_reason, p_confirm_username);
$$;
revoke all on function public.athlth_admin_manage_plus_grant(uuid,text,integer,text,text)
    from public, anon;
grant execute on function public.athlth_admin_manage_plus_grant(uuid,text,integer,text,text)
    to authenticated;

-- Preserve the paging, sorting, and owner/admin restrictions of v2. The
-- grant status is overlaid only at display time; real paid receipts survive.
create or replace function private.athlth_admin_directory_v3(
    p_search text default '',
    p_sort text default 'joined_newest',
    p_limit integer default 50,
    p_offset integer default 0
) returns table(
    user_id uuid, username text, display_name text, avatar_url text,
    account_role text, subscription_tier text, subscription_status text,
    account_state text, joined_at timestamptz, total_count bigint,
    admin_plus_grant_active boolean, admin_plus_grant_expires_at timestamptz
) language sql stable security definer set search_path = ''
as $$
    select d.user_id, d.username, d.display_name, d.avatar_url,
        d.account_role,
        case when g.user_id is not null then 'athlth_plus'::text
             else d.subscription_tier end,
        case when g.user_id is not null and d.subscription_status <> 'active'
             then 'admin_grant'::text else d.subscription_status end,
        d.account_state, d.joined_at, d.total_count,
        (g.user_id is not null),
        g.expires_at
    from private.athlth_admin_directory_v2(
        p_search, p_sort, p_limit, p_offset) d
    left join public.athlth_admin_plus_grants g
        on g.user_id = d.user_id
        and g.revoked_at is null
        and (g.expires_at is null or g.expires_at > now());
$$;
revoke all on function private.athlth_admin_directory_v3(text,text,integer,integer)
    from public, anon;
grant execute on function private.athlth_admin_directory_v3(text,text,integer,integer)
    to authenticated;

create or replace function public.athlth_admin_directory_v3(
    p_search text default '',
    p_sort text default 'joined_newest',
    p_limit integer default 50,
    p_offset integer default 0
) returns table(
    user_id uuid, username text, display_name text, avatar_url text,
    account_role text, subscription_tier text, subscription_status text,
    account_state text, joined_at timestamptz, total_count bigint,
    admin_plus_grant_active boolean, admin_plus_grant_expires_at timestamptz
) language sql stable security invoker set search_path = ''
as $$
    select * from private.athlth_admin_directory_v3(
        p_search, p_sort, p_limit, p_offset);
$$;
revoke all on function public.athlth_admin_directory_v3(text,text,integer,integer)
    from public, anon;
grant execute on function public.athlth_admin_directory_v3(text,text,integer,integer)
    to authenticated;
