-- ATHLTH 1.3.8: public route discovery for Around You

create table if not exists public.community_routes (
  id uuid primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  visibility text not null default 'public'
    check (visibility in ('private', 'friends', 'public')),
  coordinates jsonb not null,
  distance_kilometers double precision not null default 0,
  elevation_gain_meters double precision,
  start_name text,
  end_name text,
  expected_travel_time_seconds double precision,
  route_source text,
  center_latitude double precision not null,
  center_longitude double precision not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists community_routes_visibility_idx
  on public.community_routes (visibility, created_at desc);

create index if not exists community_routes_center_idx
  on public.community_routes (center_latitude, center_longitude);

alter table public.community_routes enable row level security;

drop policy if exists "public routes are readable" on public.community_routes;
create policy "public routes are readable"
  on public.community_routes
  for select
  to authenticated
  using (
    visibility = 'public'
    or owner_id = (select auth.uid())
  );

drop policy if exists "users can publish own routes" on public.community_routes;
create policy "users can publish own routes"
  on public.community_routes
  for insert
  to authenticated
  with check (owner_id = (select auth.uid()));

drop policy if exists "users can update own routes" on public.community_routes;
create policy "users can update own routes"
  on public.community_routes
  for update
  to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

drop policy if exists "users can delete own routes" on public.community_routes;
create policy "users can delete own routes"
  on public.community_routes
  for delete
  to authenticated
  using (owner_id = (select auth.uid()));

grant select, insert, update, delete on public.community_routes to authenticated;
