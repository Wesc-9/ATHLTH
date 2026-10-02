-- Route-aware Live Ghost.
-- Additive, nullable fields keep existing live workout rows and older clients compatible.

alter table public.live_workout_sessions
    add column if not exists route_key uuid,
    add column if not exists route_distance_meters double precision,
    add column if not exists route_title text;

alter table public.live_workout_locations
    add column if not exists route_progress_percent double precision,
    add column if not exists route_deviation_meters double precision;

create index if not exists live_workout_sessions_route_key_status_idx
    on public.live_workout_sessions (route_key, status, started_at desc)
    where route_key is not null;
