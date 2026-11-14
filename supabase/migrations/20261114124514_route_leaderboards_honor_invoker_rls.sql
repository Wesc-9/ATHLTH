-- Respect the existing RLS policies on route_attempts,
-- public_trail_attempts and social_profile_cards for every leaderboard query.
-- Direction-scoped views must not execute with the view owner's rights.
alter view public.route_attempt_leaderboard
  set (security_invoker = true);
alter view public.public_trail_attempt_leaderboard
  set (security_invoker = true);
