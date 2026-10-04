-- Cover the workout_gear_usage gear foreign key for deletes and joins.

create index if not exists workout_gear_usage_gear_id_idx
  on public.workout_gear_usage (gear_id);
