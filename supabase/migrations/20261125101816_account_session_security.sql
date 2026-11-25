create table if not exists private.athlth_account_login_history (
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null,
 device_kind text not null check (device_kind in ('iPhone','iPad','Other')),
 signed_in_at timestamptz not null,
 primary key(user_id,session_id)
);
alter table private.athlth_account_login_history enable row level security;
revoke all on private.athlth_account_login_history from public,anon,authenticated;

create or replace function private.athlth_my_session_id() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare sid uuid := nullif(auth.jwt()->>'session_id','')::uuid;
begin
 if auth.uid() is null or sid is null or not exists (
  select 1 from auth.sessions s where s.id=sid and s.user_id=auth.uid()
    and (s.not_after is null or s.not_after>now())
 ) then raise exception 'Session no longer valid' using errcode='42501'; end if;
 return sid;
end; $$;
revoke all on function private.athlth_my_session_id() from public,anon,authenticated;

create or replace function private.athlth_my_account_sessions(p_device_kind text default 'Other')
returns table(session_id uuid,device_kind text,signed_in_at timestamptz,last_refreshed_at timestamptz,is_current boolean,is_active boolean)
language plpgsql security definer set search_path='' as $$
declare sid uuid := private.athlth_my_session_id();
begin
 insert into private.athlth_account_login_history(user_id,session_id,device_kind,signed_in_at)
 select s.user_id,s.id,case when p_device_kind in ('iPhone','iPad') then p_device_kind else 'Other' end,s.created_at
 from auth.sessions s where s.id=sid and s.user_id=auth.uid()
 on conflict(user_id,session_id) do nothing;
 delete from private.athlth_account_login_history h where h.user_id=auth.uid() and h.signed_in_at<now()-interval '90 days'
 and not exists(select 1 from auth.sessions s where s.id=h.session_id and s.user_id=h.user_id);
 return query
 select s.id,coalesce(h.device_kind,'Other'),s.created_at,coalesce(s.refreshed_at at time zone 'UTC',s.created_at),s.id=sid,true
 from auth.sessions s left join private.athlth_account_login_history h on h.user_id=s.user_id and h.session_id=s.id
 where s.user_id=auth.uid() and (s.not_after is null or s.not_after>now())
 union all
 select h.session_id,h.device_kind,h.signed_in_at,null::timestamptz,false,false
 from private.athlth_account_login_history h
 where h.user_id=auth.uid() and h.signed_in_at>=now()-interval '90 days'
 and not exists(select 1 from auth.sessions s where s.id=h.session_id and s.user_id=h.user_id and (s.not_after is null or s.not_after>now()));
end; $$;
revoke all on function private.athlth_my_account_sessions(text) from public,anon;
grant execute on function private.athlth_my_account_sessions(text) to authenticated;
create or replace function public.athlth_my_account_sessions(p_device_kind text default 'Other')
returns table(session_id uuid,device_kind text,signed_in_at timestamptz,last_refreshed_at timestamptz,is_current boolean,is_active boolean)
language sql security invoker set search_path='' as $$
 select * from private.athlth_my_account_sessions(p_device_kind);
$$;
revoke all on function public.athlth_my_account_sessions(text) from public,anon;
grant execute on function public.athlth_my_account_sessions(text) to authenticated;

create or replace function private.athlth_revoke_my_other_session(p_session_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare sid uuid := private.athlth_my_session_id(); affected integer;
begin
 if p_session_id=sid then raise exception 'Use local sign-out' using errcode='22023'; end if;
 delete from auth.sessions s where s.id=p_session_id and s.user_id=auth.uid();
 get diagnostics affected=row_count;
 return affected=1;
end; $$;
revoke all on function private.athlth_revoke_my_other_session(uuid) from public,anon;
grant execute on function private.athlth_revoke_my_other_session(uuid) to authenticated;
create or replace function public.athlth_revoke_my_other_session(p_session_id uuid) returns boolean
language sql security invoker set search_path='' as $$
 select private.athlth_revoke_my_other_session(p_session_id);
$$;
revoke all on function public.athlth_revoke_my_other_session(uuid) from public,anon;
grant execute on function public.athlth_revoke_my_other_session(uuid) to authenticated;
