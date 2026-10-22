-- Extend existing private workout check-ins to hotels and athletics stadiums.
-- All prior fitness-center rows remain valid; existing RLS, 150 m proximity,
-- Apple Place ID storage and unique (user_id, workout_id) remain unchanged.
-- Idempotent because the same relaxation may already be applied to the project.
begin;
alter table public.workout_place_checkins
  drop constraint if exists workout_place_checkins_place_kind_check;
alter table public.workout_place_checkins
  add constraint workout_place_checkins_place_kind_check
  check (place_kind in ('fitness_center', 'hotel', 'stadium'));
commit;
