create table if not exists public.workout_place_checkins (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    workout_id uuid not null,
    apple_place_id text not null,
    place_kind text not null default 'fitness_center'
        check (place_kind in ('fitness_center')),
    checked_in_at timestamptz not null default now(),
    distance_meters double precision
        check (distance_meters is null or distance_meters >= 0),
    source text not null default 'apple_maps'
        check (source = 'apple_maps'),
    created_at timestamptz not null default now(),
    unique(user_id, workout_id)
);

create index if not exists workout_place_checkins_user_idx
    on public.workout_place_checkins(user_id, checked_in_at desc);

create index if not exists workout_place_checkins_place_idx
    on public.workout_place_checkins(apple_place_id, checked_in_at desc);

alter table public.workout_place_checkins enable row level security;

drop policy if exists "users read own workout place checkins"
    on public.workout_place_checkins;

create policy "users read own workout place checkins"
on public.workout_place_checkins
for select
to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "users insert own workout place checkins"
    on public.workout_place_checkins;

create policy "users insert own workout place checkins"
on public.workout_place_checkins
for insert
to authenticated
with check (
    user_id = (select auth.uid())
    and char_length(trim(apple_place_id)) > 0
    and (
        distance_meters is null
        or distance_meters <= 150
    )
);

drop policy if exists "users update own workout place checkins"
    on public.workout_place_checkins;

create policy "users update own workout place checkins"
on public.workout_place_checkins
for update
to authenticated
using (user_id = (select auth.uid()))
with check (
    user_id = (select auth.uid())
    and (
        distance_meters is null
        or distance_meters <= 150
    )
);

drop policy if exists "users delete own workout place checkins"
    on public.workout_place_checkins;

create policy "users delete own workout place checkins"
on public.workout_place_checkins
for delete
to authenticated
using (user_id = (select auth.uid()));

grant select, insert, update, delete
    on public.workout_place_checkins
    to authenticated;
