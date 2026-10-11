-- Arena source IDs are workout UUIDs. Prevent two athletes in one
-- competition from claiming the same recorded workout, including when
-- their respective client apps present different source labels.
-- This is a duplicate-ID safeguard, not independent source attestation.
create unique index if not exists arena_one_workout_one_athlete_per_series
 on public.arena_workout_evidence (series_id, source_workout_id);

comment on index public.arena_one_workout_one_athlete_per_series is
 'Same workout UUID cannot be claimed by two athlete slots or used in two rounds in the same Arena series.';
