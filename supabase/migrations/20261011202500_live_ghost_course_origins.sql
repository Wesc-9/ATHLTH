-- Mark the origin of Live Ghost head-to-head courses explicitly.
-- Legacy invitations remain previous-workout challenges.
-- This only adds metadata; existing friends/blocks/privacy RLS is unchanged.
alter table public.ghost_race_challenges
  add column if not exists source_kind text not null default 'previous_workout';

alter table public.ghost_race_challenges
  drop constraint if exists ghost_race_source_kind_check;
alter table public.ghost_race_challenges
  add constraint ghost_race_source_kind_check
  check (source_kind in ('previous_workout', 'planned_route'));

comment on column public.ghost_race_challenges.source_kind is
  'previous_workout uses consented prior GPS evidence; planned_route uses a user-selected route with synthetic target pacing. Neither automatically awards Arena series points.';
