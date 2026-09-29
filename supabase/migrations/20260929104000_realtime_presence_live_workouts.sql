-- Realtime social presence + live workout location foundation.
-- Lightweight by design: one mutable location row per active participant, short TTL,
-- and no route-history storage in the realtime tables.

alter table public.profile_social_settings
  add column if not exists show_online_status boolean not null default true,
  add column if not exists share_live_workout_location boolean not null default false,
  add column if not exists live_location_visibility text not null default 'followers'
    check (live_location_visibility in ('private','followers','mutuals'));

create table if not exists public.social_online_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  is_online boolean not null default false,
  device_session_id uuid,
  updated_at timestamptz not null default now()
);

create index if not exists social_online_presence_online_updated_idx
  on public.social_online_presence(is_online, updated_at desc);

create table if not exists public.live_workout_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  opponent_user_id uuid references public.profiles(id) on delete set null,
  ghost_challenge_id uuid references public.ghost_race_challenges(id) on delete set null,
  activity text not null check (activity in ('running','walking','cycling')),
  title text not null check (char_length(title) between 1 and 160),
  visibility text not null default 'followers'
    check (visibility in ('private','followers','mutuals')),
  status text not null default 'active'
    check (status in ('active','paused','completed','cancelled')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (opponent_user_id is null or opponent_user_id <> owner_id),
  check (ended_at is null or ended_at >= started_at)
);

create index if not exists live_workout_sessions_owner_status_idx
  on public.live_workout_sessions(owner_id, status, started_at desc);

create index if not exists live_workout_sessions_opponent_status_idx
  on public.live_workout_sessions(opponent_user_id, status, started_at desc)
  where opponent_user_id is not null;

create unique index if not exists live_workout_sessions_active_ghost_idx
  on public.live_workout_sessions(ghost_challenge_id)
  where ghost_challenge_id is not null
    and status in ('active','paused');

create table if not exists public.live_workout_locations (
  session_id uuid not null references public.live_workout_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  horizontal_accuracy double precision
    check (horizontal_accuracy is null or horizontal_accuracy >= 0),
  speed_meters_per_second double precision
    check (speed_meters_per_second is null or speed_meters_per_second >= 0),
  course_degrees double precision
    check (course_degrees is null or course_degrees between 0 and 360),
  distance_meters double precision not null default 0 check (distance_meters >= 0),
  elapsed_seconds double precision not null default 0 check (elapsed_seconds >= 0),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '90 seconds'),
  primary key (session_id, user_id)
);

create index if not exists live_workout_locations_expiry_idx
  on public.live_workout_locations(expires_at);

alter table public.social_online_presence enable row level security;
alter table public.live_workout_sessions enable row level security;
alter table public.live_workout_locations enable row level security;

revoke all on public.social_online_presence from anon;
revoke all on public.live_workout_sessions from anon;
revoke all on public.live_workout_locations from anon;

grant select, insert, update on public.social_online_presence to authenticated;
grant select, insert, update on public.live_workout_sessions to authenticated;
grant select, insert, update, delete on public.live_workout_locations to authenticated;

create or replace function private.is_mutual_follow(other_user uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    exists (
      select 1
      from public.profile_follows f
      where f.follower_id = (select auth.uid())
        and f.following_id = other_user
    )
    and exists (
      select 1
      from public.profile_follows f
      where f.follower_id = other_user
        and f.following_id = (select auth.uid())
    );
$$;

revoke all on function private.is_mutual_follow(uuid) from public, anon;
grant execute on function private.is_mutual_follow(uuid) to authenticated;

create or replace function private.can_view_online_status(owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and coalesce(
        (
          select s.show_online_status
          from public.profile_social_settings s
          where s.user_id = owner_id
        ),
        false
      )
      and exists (
        select 1
        from public.profile_follows f
        where f.follower_id = (select auth.uid())
          and f.following_id = owner_id
      )
    );
$$;

revoke all on function private.can_view_online_status(uuid) from public, anon;
grant execute on function private.can_view_online_status(uuid) to authenticated;

create or replace function private.can_view_live_workout(session_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from public.live_workout_sessions l
    join public.profile_social_settings s
      on s.user_id = l.owner_id
    where l.id = session_uuid
      and l.status in ('active','paused')
      and l.started_at > now() - interval '12 hours'
      and (
        l.owner_id = (select auth.uid())
        or l.opponent_user_id = (select auth.uid())
        or (
          s.share_live_workout_location
          and not private.is_blocked(l.owner_id)
          and (
            (
              l.visibility = 'followers'
              and exists (
                select 1
                from public.profile_follows f
                where f.follower_id = (select auth.uid())
                  and f.following_id = l.owner_id
              )
            )
            or (
              l.visibility = 'mutuals'
              and private.is_mutual_follow(l.owner_id)
            )
          )
        )
      )
  );
$$;

revoke all on function private.can_view_live_workout(uuid) from public, anon;
grant execute on function private.can_view_live_workout(uuid) to authenticated;

drop policy if exists social_online_presence_select_allowed
  on public.social_online_presence;
create policy social_online_presence_select_allowed
  on public.social_online_presence
  for select
  to authenticated
  using (private.can_view_online_status(user_id));

drop policy if exists social_online_presence_insert_own
  on public.social_online_presence;
create policy social_online_presence_insert_own
  on public.social_online_presence
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists social_online_presence_update_own
  on public.social_online_presence;
create policy social_online_presence_update_own
  on public.social_online_presence
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists live_workout_sessions_select_allowed
  on public.live_workout_sessions;
create policy live_workout_sessions_select_allowed
  on public.live_workout_sessions
  for select
  to authenticated
  using (private.can_view_live_workout(id));

drop policy if exists live_workout_sessions_insert_own
  on public.live_workout_sessions;
create policy live_workout_sessions_insert_own
  on public.live_workout_sessions
  for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    and (
      opponent_user_id is null
      or not private.is_blocked(opponent_user_id)
    )
  );

drop policy if exists live_workout_sessions_update_participant
  on public.live_workout_sessions;
create policy live_workout_sessions_update_participant
  on public.live_workout_sessions
  for update
  to authenticated
  using (
    owner_id = (select auth.uid())
    or opponent_user_id = (select auth.uid())
  )
  with check (
    owner_id = owner_id
  );

drop policy if exists live_workout_locations_select_allowed
  on public.live_workout_locations;
create policy live_workout_locations_select_allowed
  on public.live_workout_locations
  for select
  to authenticated
  using (
    expires_at > now()
    and private.can_view_live_workout(session_id)
  );

drop policy if exists live_workout_locations_insert_participant
  on public.live_workout_locations;
create policy live_workout_locations_insert_participant
  on public.live_workout_locations
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.live_workout_sessions l
      where l.id = session_id
        and l.status in ('active','paused')
        and (
          l.owner_id = (select auth.uid())
          or l.opponent_user_id = (select auth.uid())
        )
    )
  );

drop policy if exists live_workout_locations_update_participant
  on public.live_workout_locations;
create policy live_workout_locations_update_participant
  on public.live_workout_locations
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1
      from public.live_workout_sessions l
      where l.id = session_id
        and l.status in ('active','paused')
        and (
          l.owner_id = (select auth.uid())
          or l.opponent_user_id = (select auth.uid())
        )
    )
  );

drop policy if exists live_workout_locations_delete_participant
  on public.live_workout_locations;
create policy live_workout_locations_delete_participant
  on public.live_workout_locations
  for delete
  to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.begin_ghost_live_session(
  p_challenge_id uuid
)
returns public.live_workout_sessions
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  challenge public.ghost_race_challenges%rowtype;
  existing public.live_workout_sessions%rowtype;
  created public.live_workout_sessions%rowtype;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_challenge_id::text));

  select *
  into challenge
  from public.ghost_race_challenges
  where id = p_challenge_id;

  if not found
     or challenge.status <> 'accepted'
     or challenge.expires_at <= now()
     or actor not in (challenge.sender_id, challenge.recipient_id) then
    raise exception 'Ghost Race is not available for live start';
  end if;

  select *
  into existing
  from public.live_workout_sessions
  where ghost_challenge_id = p_challenge_id
    and status in ('active','paused')
  order by started_at desc
  limit 1;

  if found then
    return existing;
  end if;

  insert into public.live_workout_sessions (
    owner_id,
    opponent_user_id,
    ghost_challenge_id,
    activity,
    title,
    visibility,
    status
  )
  values (
    challenge.sender_id,
    challenge.recipient_id,
    challenge.id,
    'running',
    challenge.title,
    'private',
    'active'
  )
  returning * into created;

  return created;
end;
$$;

revoke all on function public.begin_ghost_live_session(uuid) from public, anon;
grant execute on function public.begin_ghost_live_session(uuid) to authenticated;

create or replace function public.prune_stale_live_workout_state()
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  delete from public.live_workout_locations
  where expires_at <= now();

  update public.live_workout_sessions
  set status = 'completed',
      ended_at = coalesce(ended_at, now()),
      updated_at = now()
  where status in ('active','paused')
    and started_at < now() - interval '12 hours';
end;
$$;

revoke all on function public.prune_stale_live_workout_state() from public, anon;
grant execute on function public.prune_stale_live_workout_state() to authenticated;

drop trigger if exists live_workout_sessions_updated_at
  on public.live_workout_sessions;
create trigger live_workout_sessions_updated_at
before update on public.live_workout_sessions
for each row execute function public.set_updated_at();
