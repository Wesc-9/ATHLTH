-- ATHLTH: automatic account-scoped sync of completed STRENGTH training records.
-- App uploads only a minimal workout DTO; never raw HealthKit, HR/HRV,
-- sleep, GPS or free-text clinical observations. Completed workouts are
-- append-only so an older/offline device cannot overwrite later results.
-- Account deletion cascades. This is not a public workout feed.
create table if not exists public.account_strength_workout_sync (
    user_id uuid not null references auth.users(id) on delete cascade,
    workout_id uuid not null,
    started_at timestamptz not null,
    ended_at timestamptz not null,
    document jsonb not null,
    created_at timestamptz not null default now(),
    primary key (user_id, workout_id),
    constraint account_strength_workout_sync_valid_document check (
        jsonb_typeof(document) = 'object'
        and document ->> 'id' = workout_id::text
        and jsonb_typeof(document -> 'exercises') = 'array'
        and not document ? 'healthMetrics'
        and not document ? 'watchSessionID'
        and not document ? 'plannedTrainingPlace'
        and not document ? 'liveHeartRateTargetZone'
        and not jsonb_path_exists(document, '$.exercises[*].targetHeartRateZone')
        and not jsonb_path_exists(document, '$.exercises[*].sets[*].watchAverageHeartRateBPM')
        and not jsonb_path_exists(document, '$.exercises[*].sets[*].watchMaximumHeartRateBPM')
        and not jsonb_path_exists(document, '$.exercises[*].sets[*].hybridTargetHeartRateZone')
        and not jsonb_path_exists(document, '$.exercises[*].sets[*].plannedNote')
    ),
    constraint account_strength_workout_sync_valid_times check (
        ended_at >= started_at
    )
);

create index if not exists account_strength_workout_sync_recent_idx
    on public.account_strength_workout_sync(user_id, ended_at desc, workout_id);

alter table public.account_strength_workout_sync enable row level security;
revoke all on table public.account_strength_workout_sync from public, anon;
grant select, insert on public.account_strength_workout_sync to authenticated;

create policy account_strength_workout_owner_read
    on public.account_strength_workout_sync
    for select to authenticated
    using (user_id = (select auth.uid()));

create policy account_strength_workout_owner_insert
    on public.account_strength_workout_sync
    for insert to authenticated
    with check (user_id = (select auth.uid()));

comment on table public.account_strength_workout_sync is
    'Owner-only append-only completed workout training metrics for automatic iPhone/iPad/Watch relay. No raw HealthKit, HRV, sleep, GPS or heart rate.';
