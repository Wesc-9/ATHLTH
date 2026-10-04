create table if not exists public.route_attempts (
    id uuid primary key default gen_random_uuid(),
    route_id uuid not null references public.community_routes(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    workout_id uuid not null,
    activity_type text not null default 'running'
        check (activity_type in ('running','walking')),
    started_at timestamptz not null,
    duration_seconds double precision not null
        check (duration_seconds > 0),
    distance_meters double precision not null default 0
        check (distance_meters >= 0),
    route_match_percent double precision not null
        check (route_match_percent >= 0 and route_match_percent <= 100),
    average_deviation_meters double precision
        check (average_deviation_meters is null or average_deviation_meters >= 0),
    max_deviation_meters double precision
        check (max_deviation_meters is null or max_deviation_meters >= 0),
    source text not null default 'apple_health'
        check (source in ('apple_health','apple_watch','athlth')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique(route_id, user_id, workout_id)
);

create index if not exists route_attempts_route_started_idx
    on public.route_attempts(route_id, started_at desc);

create index if not exists route_attempts_route_duration_idx
    on public.route_attempts(route_id, duration_seconds asc);

create index if not exists route_attempts_user_idx
    on public.route_attempts(user_id, started_at desc);

alter table public.route_attempts enable row level security;

drop policy if exists "public routes are readable" on public.community_routes;
drop policy if exists "routes_read_allowed" on public.community_routes;

create policy "routes_read_allowed"
on public.community_routes
for select
to authenticated
using (
    owner_id = (select auth.uid())
    or visibility = 'public'
    or (
        visibility = 'friends'
        and exists (
            select 1
            from public.friendships f
            where
                (f.user_a = owner_id and f.user_b = (select auth.uid()))
                or
                (f.user_b = owner_id and f.user_a = (select auth.uid()))
        )
    )
);

drop policy if exists "route_attempts_select_allowed" on public.route_attempts;
create policy "route_attempts_select_allowed"
on public.route_attempts
for select
to authenticated
using (
    user_id = (select auth.uid())
    or (
        private.can_view_profile_card(user_id)
        and exists (
            select 1
            from public.community_routes r
            where r.id = route_id
              and (
                  r.owner_id = (select auth.uid())
                  or r.visibility = 'public'
                  or (
                      r.visibility = 'friends'
                      and exists (
                          select 1
                          from public.friendships f
                          where
                              (f.user_a = r.owner_id and f.user_b = (select auth.uid()))
                              or
                              (f.user_b = r.owner_id and f.user_a = (select auth.uid()))
                      )
                  )
              )
        )
    )
);

drop policy if exists "route_attempts_insert_own" on public.route_attempts;
create policy "route_attempts_insert_own"
on public.route_attempts
for insert
to authenticated
with check (
    user_id = (select auth.uid())
    and exists (
        select 1
        from public.community_routes r
        where r.id = route_id
    )
);

drop policy if exists "route_attempts_update_own" on public.route_attempts;
create policy "route_attempts_update_own"
on public.route_attempts
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists "route_attempts_delete_own" on public.route_attempts;
create policy "route_attempts_delete_own"
on public.route_attempts
for delete
to authenticated
using (user_id = (select auth.uid()));
