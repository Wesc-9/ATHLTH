-- ATHLTH 1.4.5: OpenStreetMap Trail Mode + independent trail leaderboards.
-- Public trails stay separate from user-created community_routes so this
-- feature can be disabled or evolved without destabilising existing routes.

create table if not exists public.public_trails (
    id uuid primary key default gen_random_uuid(),
    osm_relation_id bigint not null unique,
    name text not null check (char_length(trim(name)) between 1 and 180),
    route_kind text not null
        check (route_kind in ('hiking', 'foot')),
    network text,
    reference text,
    operator_name text,
    symbol text,
    coordinates jsonb not null,
    distance_kilometers double precision not null
        check (distance_kilometers >= 0.5),
    center_latitude double precision not null,
    center_longitude double precision not null,
    leaderboard_enabled boolean not null default false,
    athlth_verified boolean not null default false,
    source text not null default 'openstreetmap'
        check (source = 'openstreetmap'),
    source_updated_at timestamptz,
    last_fetched_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists public_trails_center_idx
    on public.public_trails(center_latitude, center_longitude);

create index if not exists public_trails_kind_distance_idx
    on public.public_trails(route_kind, distance_kilometers);

alter table public.public_trails enable row level security;

drop policy if exists "authenticated can read public trails"
    on public.public_trails;

create policy "authenticated can read public trails"
on public.public_trails
for select
to authenticated
using (true);

grant select on public.public_trails to authenticated;

create table if not exists public.public_trail_fetch_cells (
    cell_key text primary key,
    center_latitude double precision not null,
    center_longitude double precision not null,
    radius_kilometers double precision not null,
    fetched_at timestamptz not null default now()
);

alter table public.public_trail_fetch_cells enable row level security;

create table if not exists public.public_trail_attempts (
    id uuid primary key default gen_random_uuid(),
    trail_id uuid not null
        references public.public_trails(id) on delete cascade,
    user_id uuid not null
        references public.profiles(id) on delete cascade,
    workout_id uuid not null,
    activity_type text not null
        check (activity_type in ('running', 'walking', 'hiking')),
    started_at timestamptz not null,
    duration_seconds double precision not null
        check (duration_seconds > 0),
    distance_meters double precision not null
        check (distance_meters >= 0),
    route_match_percent double precision not null
        check (route_match_percent >= 0 and route_match_percent <= 100),
    average_deviation_meters double precision,
    max_deviation_meters double precision,
    source text not null default 'apple_health'
        check (source in ('apple_health', 'apple_watch', 'athlth')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(trail_id, user_id, workout_id)
);

create index if not exists public_trail_attempts_trail_time_idx
    on public.public_trail_attempts(
        trail_id,
        activity_type,
        duration_seconds
    );

create index if not exists public_trail_attempts_user_idx
    on public.public_trail_attempts(user_id, started_at desc);

alter table public.public_trail_attempts enable row level security;

drop policy if exists "trail attempts readable"
    on public.public_trail_attempts;

create policy "trail attempts readable"
on public.public_trail_attempts
for select
to authenticated
using (
    user_id = (select auth.uid())
    or private.can_view_profile_card(user_id)
);

drop policy if exists "users insert own trail attempts"
    on public.public_trail_attempts;

create policy "users insert own trail attempts"
on public.public_trail_attempts
for insert
to authenticated
with check (
    user_id = (select auth.uid())
    and exists (
        select 1
        from public.public_trails t
        where t.id = trail_id
          and t.leaderboard_enabled
          and t.distance_kilometers >= 1.0
    )
);

drop policy if exists "users update own trail attempts"
    on public.public_trail_attempts;

create policy "users update own trail attempts"
on public.public_trail_attempts
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "users delete own trail attempts"
    on public.public_trail_attempts;

create policy "users delete own trail attempts"
on public.public_trail_attempts
for delete
to authenticated
using (user_id = (select auth.uid()));

grant select, insert, update, delete
    on public.public_trail_attempts
    to authenticated;

create or replace view public.public_trail_attempt_leaderboard
with (security_invoker = true)
as
select
    a.id,
    a.trail_id,
    a.user_id,
    a.workout_id,
    a.activity_type,
    a.started_at,
    a.duration_seconds,
    a.distance_meters,
    a.route_match_percent,
    a.average_deviation_meters,
    a.max_deviation_meters,
    a.source,
    c.username::text as username,
    c.display_name,
    c.avatar_url
from public.public_trail_attempts a
join public.social_profile_cards c
  on c.user_id = a.user_id;

grant select on public.public_trail_attempt_leaderboard
    to authenticated;
