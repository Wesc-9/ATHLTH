-- Allow walking challenges in the shared friend-challenge backend.
-- Keep all currently supported app values in the constraint.

alter table public.social_challenges
  drop constraint if exists social_challenges_sport_check;

alter table public.social_challenges
  add constraint social_challenges_sport_check
  check (sport in ('running','walking','strength','heartRate'));
