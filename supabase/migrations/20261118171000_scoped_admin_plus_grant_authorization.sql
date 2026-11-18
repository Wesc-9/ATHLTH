-- Admins can manage complimentary Plus for ordinary users only. Only the
-- owner can grant to other admin accounts. Nobody can manage their own grant.
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
    v_actor_role text;
    v_role text;
    v_username text;
    v_reason text := trim(coalesce(p_reason, ''));
    v_expiry timestamptz;
    v_rows integer;
begin
    select role into v_actor_role from public.account_roles
        where user_id = v_actor;
    if v_actor is null or coalesce(v_actor_role, '') not in ('owner', 'admin') then
        raise exception 'Administrator permission required' using errcode = '42501';
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
       or (v_actor_role = 'admin' and v_role <> 'user')
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
