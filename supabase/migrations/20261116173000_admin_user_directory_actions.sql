-- ATHLTH Studio account support: least-privilege directory and audited role changes.
-- This adds no access to messages, HealthKit, private workouts, or contact emails.
-- Security: only authenticated owner can mutate roles; owner cannot be
-- edited from Studio. Suspending auth access requires the separate server-only
-- Edge Function. Deletion is a review request, never a blind cascade.
--
-- Subscription status is computed from effective dates, not tier alone.
-- StoreKit entitlement source remains the authority for App Store plans.

create table if not exists public.athlth_admin_account_audit (
    id uuid primary key default gen_random_uuid(),
    actor_id uuid not null,
    target_id uuid not null,
    action text not null check (length(action) between 3 and 50),
    reason text not null check (length(reason) between 10 and 500),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);
alter table public.athlth_admin_account_audit enable row level security;
revoke all on public.athlth_admin_account_audit from public, anon, authenticated;
-- Service role can log server-only suspension requests; private function below
-- writes role changes as the SECURITY DEFINER owner.

create table if not exists public.athlth_admin_deletion_requests (
    id uuid primary key default gen_random_uuid(),
    requested_by uuid not null,
    target_id uuid not null,
    reason text not null check (length(reason) between 10 and 500),
    state text not null default 'pending' check (state in ('pending','reviewed','rejected','completed')),
    created_at timestamptz not null default now(),
    reviewed_at timestamptz
);
create unique index if not exists athlth_admin_deletion_pending_once
    on public.athlth_admin_deletion_requests(target_id) where state = 'pending';
alter table public.athlth_admin_deletion_requests enable row level security;
revoke all on public.athlth_admin_deletion_requests from public, anon, authenticated;

create or replace function private.athlth_admin_directory_v2(
    p_search text default '',
    p_sort text default 'joined_newest',
    p_limit integer default 50,
    p_offset integer default 0
)
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_url text,
    account_role text,
    subscription_tier text,
    subscription_status text,
    account_state text,
    joined_at timestamptz,
    total_count bigint
)
language plpgsql
stable security definer
set search_path = ''
as $$
begin
    if (select auth.uid()) is null or not (select private.is_app_admin()) then
        raise exception 'Access denied' using errcode = '42501';
    end if;
    if coalesce(p_sort,'') not in
       ('joined_newest','joined_oldest','name','role','subscription','status') then
        raise exception 'Unsupported sort' using errcode = '22023';
    end if;

    return query
    with accounts as (
        select p.id as uid,
               p.username::text as handle,
               p.display_name as shown_name,
               p.avatar_url as picture,
               coalesce(r.role,'user') as role_name,
               case
                 when e.tier = 'athlth_plus' and
                    ((e.status = 'trialing' and e.trial_ends_at > now()) or
                     (e.status = 'active' and
                        (e.source = 'admin' or
                         (e.source = 'app_store' and e.current_period_ends_at > now()))))
                 then 'athlth_plus'
                 else 'free'
               end as effective_tier,
               case
                 when e.user_id is null then 'free'
                 when e.status = 'trialing' and e.trial_ends_at > now() then 'trialing'
                 when e.status = 'trialing' then 'trial_expired'
                 when e.status = 'active' and e.source = 'admin' then 'admin_grant'
                 when e.status = 'active' and e.source = 'app_store' and e.current_period_ends_at > now() then 'active'
                 when e.status = 'active' then 'expired'
                 else coalesce(e.status,'unknown')
               end as subscription_state,
               case when u.banned_until > now() then 'suspended'
                    else 'active'
               end as account_lifecycle,
               p.created_at as joined
        from public.profiles p
        join auth.users u on u.id = p.id and u.deleted_at is null
        left join public.account_roles r on r.user_id = p.id
        left join public.subscription_entitlements e on e.user_id = p.id
    )
    select a.uid, a.handle, a.shown_name, a.picture, a.role_name,
           a.effective_tier, a.subscription_state, a.account_lifecycle,
           a.joined, count(*) over()
    from accounts a
    where length(trim(coalesce(p_search,''))) = 0
       or position(lower(left(trim(p_search),80)) in
            lower(coalesce(a.handle,'') || ' ' || coalesce(a.shown_name,''))) > 0
    order by
      case when p_sort = 'role' then
          case a.role_name when 'owner' then 0 when 'admin' then 1 else 2 end end asc,
      case when p_sort = 'name' then
          lower(coalesce(nullif(a.shown_name,''), a.handle,'')) end asc,
      case when p_sort = 'subscription' then
          case a.subscription_state when 'active' then 0 when 'admin_grant' then 1
            when 'trialing' then 2 when 'free' then 3 else 4 end end asc,
      case when p_sort = 'status' then a.account_lifecycle end asc,
      case when p_sort = 'joined_oldest' then a.joined end asc,
      case when p_sort = 'joined_newest' then a.joined end desc,
      a.uid
    limit least(greatest(coalesce(p_limit,50),1),100)
    offset least(greatest(coalesce(p_offset,0),0),100000);
end;
$$;
revoke all on function private.athlth_admin_directory_v2(text,text,integer,integer)
 from public,anon;
grant execute on function private.athlth_admin_directory_v2(text,text,integer,integer)
 to authenticated;

create or replace function public.athlth_admin_directory_v2(
    p_search text default '',
    p_sort text default 'joined_newest',
    p_limit integer default 50,
    p_offset integer default 0
)
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_url text,
    account_role text,
    subscription_tier text,
    subscription_status text,
    account_state text,
    joined_at timestamptz,
    total_count bigint
)
language sql stable security invoker
set search_path = ''
as $$
    select * from private.athlth_admin_directory_v2(p_search,p_sort,p_limit,p_offset);
$$;
revoke all on function public.athlth_admin_directory_v2(text,text,integer,integer)
 from public,anon;
grant execute on function public.athlth_admin_directory_v2(text,text,integer,integer)
 to authenticated;

create or replace function private.athlth_admin_change_role(
    p_target uuid,
    p_role text,
    p_reason text
)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
declare
    actor_id uuid := (select auth.uid());
    target_role text;
begin
    if actor_id is null or not exists (
        select 1 from public.account_roles
        where user_id = actor_id and role = 'owner'
    ) then
        raise exception 'Owner permission required' using errcode = '42501';
    end if;
    if p_target is null or p_target = actor_id or p_role not in ('user','admin')
       or length(trim(coalesce(p_reason,''))) not between 10 and 500 then
        raise exception 'Invalid role change request' using errcode = '22023';
    end if;

    select role into target_role from public.account_roles
      where user_id = p_target for update;
    if not found or target_role = 'owner' then
        raise exception 'Account may not be edited' using errcode = '42501';
    end if;
    if target_role = p_role then return true; end if;

    update public.account_roles set role=p_role, updated_at=now()
     where user_id=p_target;
    insert into public.athlth_admin_account_audit
      (actor_id,target_id,action,reason,metadata)
    values
      (actor_id,p_target,'role_changed',trim(p_reason),
       jsonb_build_object('from',target_role,'to',p_role));
    return true;
end;
$$;
revoke all on function private.athlth_admin_change_role(uuid,text,text) from public,anon;
grant execute on function private.athlth_admin_change_role(uuid,text,text) to authenticated;

create or replace function public.athlth_admin_change_role(
    p_target uuid,
    p_role text,
    p_reason text
)
returns boolean
language sql security invoker set search_path = ''
as $$ select private.athlth_admin_change_role(p_target,p_role,p_reason); $$;
revoke all on function public.athlth_admin_change_role(uuid,text,text) from public,anon;
grant execute on function public.athlth_admin_change_role(uuid,text,text) to authenticated;
