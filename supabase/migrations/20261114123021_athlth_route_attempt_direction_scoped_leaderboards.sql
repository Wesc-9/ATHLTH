-- Versioned route results: do not guess direction for historical GPS attempts.
alter table public.route_attempts
  add column if not exists direction text not null default 'unknown'
    check (direction in ('forward', 'reverse', 'unknown'));

alter table public.public_trail_attempts
  add column if not exists direction text not null default 'unknown'
    check (direction in ('forward', 'reverse', 'unknown'));

-- Preserve all pre-existing leaderboard columns and user permissions.
-- Append direction so older consumers keep their existing column order.
create or replace view public.route_attempt_leaderboard as
select a.id, a.route_id, a.user_id, a.workout_id, a.activity_type,
       a.started_at, a.duration_seconds, a.distance_meters,
       a.route_match_percent, a.average_deviation_meters,
       a.max_deviation_meters, a.source,
       c.username::text as username, c.display_name, c.avatar_url,
       a.direction
from public.route_attempts a
join public.social_profile_cards c on c.user_id = a.user_id;

create or replace view public.public_trail_attempt_leaderboard as
select a.id, a.trail_id, a.user_id, a.workout_id, a.activity_type,
       a.started_at, a.duration_seconds, a.distance_meters,
       a.route_match_percent, a.average_deviation_meters,
       a.max_deviation_meters, a.source,
       c.username::text as username, c.display_name, c.avatar_url,
       a.direction
from public.public_trail_attempts a
join public.social_profile_cards c on c.user_id = a.user_id;
