-- ATHLTH 1.3.9: private Gear V2 details and idempotent workout↔gear usage

create table if not exists public.profile_gear_details (
  gear_id uuid primary key references public.profile_gear(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  brand text check (brand is null or char_length(trim(brand)) <= 60),
  model text check (model is null or char_length(trim(model)) <= 80),
  color_name text check (color_name is null or char_length(trim(color_name)) <= 60),
  purchased_at date,
  first_used_at date,
  size_label text check (size_label is null or char_length(trim(size_label)) <= 30),
  shoe_use_type text check (
    shoe_use_type is null or
    shoe_use_type in ('daily', 'tempo', 'race', 'trail', 'treadmill', 'other')
  ),
  gear_type_label text check (
    gear_type_label is null or char_length(trim(gear_type_label)) <= 60
  ),
  status text not null default 'active'
    check (status in ('active', 'retired')),
  retired_at timestamptz,
  replacement_target_km double precision
    check (
      replacement_target_km is null or
      (replacement_target_km > 0 and replacement_target_km <= 5000)
    ),
  is_default_for_running boolean not null default false,
  notes text check (notes is null or char_length(notes) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profile_gear_details_dates_check
    check (
      first_used_at is null or
      purchased_at is null or
      first_used_at >= purchased_at
    )
);

create index if not exists profile_gear_details_user_idx
  on public.profile_gear_details (user_id, status, updated_at desc);

create unique index if not exists profile_gear_one_default_running_item
  on public.profile_gear_details (user_id)
  where is_default_for_running and status = 'active';

alter table public.profile_gear_details enable row level security;

create policy "users can view their own gear details"
  on public.profile_gear_details
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "users can add their own gear details"
  on public.profile_gear_details
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profile_gear g
      where g.id = gear_id
        and g.user_id = (select auth.uid())
    )
  );

create policy "users can update their own gear details"
  on public.profile_gear_details
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profile_gear g
      where g.id = gear_id
        and g.user_id = (select auth.uid())
    )
  );

create policy "users can delete their own gear details"
  on public.profile_gear_details
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.profile_gear_details
  to authenticated;

create table if not exists public.workout_gear_usage (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  workout_id uuid not null,
  gear_id uuid not null references public.profile_gear(id) on delete cascade,
  workout_title text not null
    check (char_length(trim(workout_title)) between 1 and 160),
  activity_type text not null
    check (char_length(trim(activity_type)) between 1 and 60),
  source text not null
    check (char_length(trim(source)) between 1 and 80),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_seconds double precision not null default 0
    check (duration_seconds >= 0),
  distance_meters double precision
    check (distance_meters is null or distance_meters >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, workout_id, gear_id)
);

create index if not exists workout_gear_usage_user_workout_idx
  on public.workout_gear_usage (user_id, workout_id);

create index if not exists workout_gear_usage_user_gear_idx
  on public.workout_gear_usage (user_id, gear_id, started_at desc);

alter table public.workout_gear_usage enable row level security;

create policy "users can view their own workout gear usage"
  on public.workout_gear_usage
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "users can add their own workout gear usage"
  on public.workout_gear_usage
  for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profile_gear g
      where g.id = gear_id
        and g.user_id = (select auth.uid())
    )
  );

create policy "users can update their own workout gear usage"
  on public.workout_gear_usage
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
      from public.profile_gear g
      where g.id = gear_id
        and g.user_id = (select auth.uid())
    )
  );

create policy "users can delete their own workout gear usage"
  on public.workout_gear_usage
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, update, delete
  on public.workout_gear_usage
  to authenticated;
