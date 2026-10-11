-- ATHLTH Arena: secure, collaborative pre-start competition series.
-- Does not modify existing single, Club or Weekly Challenge tables.
create table if not exists public.arena_series (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 80),
  scope text not null check (scope in ('duel','friends')),
  scoring text not null check (scoring in ('winner','podium')),
  duration_days int not null check (duration_days between 1 and 90),
  status text not null default 'draft' check (status in ('draft','active','completed','cancelled')),
  created_at timestamptz not null default now(),
  check (status = 'draft')
);

create table if not exists public.arena_series_members (
  series_id uuid not null references public.arena_series(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  response text not null default 'invited' check (response in ('invited','accepted','declined')),
  created_at timestamptz not null default now(),
  primary key (series_id,user_id)
);

create table if not exists public.arena_round_proposals (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.arena_series(id) on delete cascade,
  proposed_by uuid not null references public.profiles(id) on delete cascade,
  template text not null check (template in ('fastest5K','fastest1K','mostDistance','mostWorkouts','mostRepetitions','custom')),
  title text not null check (char_length(btrim(title)) between 1 and 80),
  rules text not null check (char_length(btrim(rules)) between 1 and 600),
  position int not null default 0 check (position between 0 and 100),
  created_at timestamptz not null default now()
);

create table if not exists public.arena_round_approvals (
  round_id uuid not null references public.arena_round_proposals(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (round_id,user_id)
);

create index if not exists arena_members_user_idx on public.arena_series_members(user_id, response);
create index if not exists arena_round_series_idx on public.arena_round_proposals(series_id, position, created_at);
create index if not exists arena_series_owner_idx on public.arena_series(owner_id, created_at desc);
create index if not exists arena_rounds_proposer_idx
  on public.arena_round_proposals(proposed_by, created_at desc);
create index if not exists arena_votes_user_idx
  on public.arena_round_approvals(user_id, created_at desc);

create schema if not exists private;

create or replace function private.arena_can_access(p_series_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select (select auth.uid()) is not null and (
    exists (
      select 1 from public.arena_series s
      where s.id = p_series_id and s.owner_id = (select auth.uid())
    )
    or exists (
      select 1 from public.arena_series_members m
      where m.series_id = p_series_id
        and m.user_id = (select auth.uid())
        and m.response in ('invited','accepted')
    )
  );
$$;

create or replace function private.arena_can_invite(p_user_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select p_user_id <> (select auth.uid())
    and (select auth.uid()) is not null
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = p_user_id and b.blocked_id = (select auth.uid()))
         or (b.blocker_id = (select auth.uid()) and b.blocked_id = p_user_id)
    )
    and exists (
      select 1 from public.profile_social_settings prefs
      where prefs.user_id = p_user_id
        and (
          prefs.allow_challenge_invites = 'everyone'
          or (
            prefs.allow_challenge_invites = 'friends'
            and exists (
              select 1 from public.profile_follows f
              where f.follower_id = (select auth.uid())
                and f.following_id = p_user_id
            )
            and exists (
              select 1 from public.profile_follows f
              where f.follower_id = p_user_id
                and f.following_id = (select auth.uid())
            )
          )
        )
    );
$$;

create or replace function private.arena_auto_accept_owner()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
begin
  insert into public.arena_series_members(series_id,user_id,response)
  values(new.id,new.owner_id,'accepted');
  return new;
end;
$$;

drop trigger if exists arena_series_creator_membership on public.arena_series;
create trigger arena_series_creator_membership
after insert on public.arena_series
for each row execute function private.arena_auto_accept_owner();

revoke all on function private.arena_can_access(uuid) from public, anon;
revoke all on function private.arena_can_invite(uuid) from public, anon;
revoke all on function private.arena_auto_accept_owner() from public, anon, authenticated;
grant usage on schema private to authenticated;
grant execute on function private.arena_can_access(uuid) to authenticated;
grant execute on function private.arena_can_invite(uuid) to authenticated;

alter table public.arena_series enable row level security;
alter table public.arena_series_members enable row level security;
alter table public.arena_round_proposals enable row level security;
alter table public.arena_round_approvals enable row level security;

revoke all on public.arena_series, public.arena_series_members,
  public.arena_round_proposals, public.arena_round_approvals from anon, authenticated;
grant select, insert, delete on public.arena_series to authenticated;
grant select, insert on public.arena_series_members to authenticated;
grant update(response) on public.arena_series_members to authenticated;
grant select, insert, delete on public.arena_round_proposals to authenticated;
grant select, insert on public.arena_round_approvals to authenticated;

drop policy if exists arena_series_read on public.arena_series;
create policy arena_series_read on public.arena_series
for select to authenticated using (private.arena_can_access(id));

drop policy if exists arena_series_insert on public.arena_series;
create policy arena_series_insert on public.arena_series
for insert to authenticated
with check (owner_id = (select auth.uid()) and status = 'draft');

drop policy if exists arena_series_delete on public.arena_series;
create policy arena_series_delete on public.arena_series
for delete to authenticated using (
  owner_id = (select auth.uid()) and status = 'draft'
);

drop policy if exists arena_members_read on public.arena_series_members;
create policy arena_members_read on public.arena_series_members
for select to authenticated
using (private.arena_can_access(series_id));

drop policy if exists arena_members_invite on public.arena_series_members;
create policy arena_members_invite on public.arena_series_members
for insert to authenticated with check (
  response = 'invited'
  and private.arena_can_invite(user_id)
  and exists (
    select 1 from public.arena_series s
    where s.id = series_id and s.owner_id = (select auth.uid())
      and s.status = 'draft'
  )
);

drop policy if exists arena_members_respond on public.arena_series_members;
create policy arena_members_respond on public.arena_series_members
for update to authenticated
using (user_id = (select auth.uid()) and response = 'invited')
with check (user_id = (select auth.uid()) and response in ('accepted','declined'));

drop policy if exists arena_rounds_read on public.arena_round_proposals;
create policy arena_rounds_read on public.arena_round_proposals
for select to authenticated using (private.arena_can_access(series_id));

drop policy if exists arena_rounds_propose on public.arena_round_proposals;
create policy arena_rounds_propose on public.arena_round_proposals
for insert to authenticated with check (
  proposed_by = (select auth.uid())
  and exists (
    select 1 from public.arena_series_members m
    join public.arena_series s on s.id = m.series_id
    where m.series_id = arena_round_proposals.series_id
      and m.user_id = (select auth.uid())
      and m.response = 'accepted' and s.status = 'draft'
  )
);

drop policy if exists arena_rounds_remove_unvoted on public.arena_round_proposals;
create policy arena_rounds_remove_unvoted on public.arena_round_proposals
for delete to authenticated using (
  proposed_by = (select auth.uid())
  and not exists (
    select 1 from public.arena_round_approvals a where a.round_id = id
  )
);

drop policy if exists arena_approvals_read on public.arena_round_approvals;
create policy arena_approvals_read on public.arena_round_approvals
for select to authenticated using (
  exists (
    select 1 from public.arena_round_proposals r
    where r.id = round_id and private.arena_can_access(r.series_id)
  )
);

drop policy if exists arena_approvals_vote on public.arena_round_approvals;
create policy arena_approvals_vote on public.arena_round_approvals
for insert to authenticated with check (
  user_id = (select auth.uid())
  and exists (
    select 1
    from public.arena_round_proposals r
    join public.arena_series_members m on m.series_id = r.series_id
    join public.arena_series s on s.id = r.series_id
    where r.id = round_id
      and m.user_id = (select auth.uid())
      and m.response = 'accepted'
      and s.status = 'draft'
  )
);

-- Publishing is atomic: a rejected invite does not leave an orphaned series.
create or replace function public.arena_publish_series(
  p_title text,
  p_scope text,
  p_scoring text,
  p_duration_days int,
  p_invitees uuid[],
  p_rounds jsonb
) returns uuid
language plpgsql security invoker
set search_path = pg_catalog, public, private
as $$
declare
  v_id uuid;
  v_actor uuid := (select auth.uid());
  v_rec jsonb;
  v_friend uuid;
  v_order integer := 0;
begin
  if v_actor is null then raise exception 'Sign in required'; end if;
  if p_scope not in ('duel','friends') then
    raise exception 'Club series require a verified Club membership workflow';
  end if;
  if coalesce(cardinality(p_invitees),0) < 1 or cardinality(p_invitees) > 20 then
    raise exception 'Invite between 1 and 20 participants';
  end if;
  if p_scope = 'duel' and cardinality(p_invitees) <> 1 then
    raise exception 'A duel requires exactly one opponent';
  end if;
  if (select count(distinct x) from unnest(p_invitees) x) <> cardinality(p_invitees)
     or v_actor = any(p_invitees) then
    raise exception 'Invitees must be distinct from the organizer';
  end if;
  if jsonb_typeof(p_rounds) is distinct from 'array'
     or jsonb_array_length(p_rounds) not between 1 and 16 then
    raise exception 'A series requires between 1 and 16 rounds';
  end if;

  insert into public.arena_series(owner_id,title,scope,scoring,duration_days)
  values(v_actor,p_title,p_scope,p_scoring,p_duration_days)
  returning id into v_id;

  foreach v_friend in array p_invitees loop
    insert into public.arena_series_members(series_id,user_id,response)
    values(v_id,v_friend,'invited');
  end loop;

  for v_rec in select value from jsonb_array_elements(p_rounds) loop
    insert into public.arena_round_proposals(
      series_id,proposed_by,template,title,rules,position
    ) values (
      v_id,v_actor,v_rec->>'template',v_rec->>'title',
      v_rec->>'rules',v_order
    );
    v_order := v_order + 1;
  end loop;
  return v_id;
end;
$$;

revoke all on function public.arena_publish_series(
  text,text,text,int,uuid[],jsonb
) from public, anon;
grant execute on function public.arena_publish_series(
  text,text,text,int,uuid[],jsonb
) to authenticated;
