create or replace view public.route_attempt_leaderboard
with (security_invoker = true)
as
select
    a.id,
    a.route_id,
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
from public.route_attempts a
join public.social_profile_cards c
  on c.user_id = a.user_id;

grant select on public.route_attempt_leaderboard to authenticated;
