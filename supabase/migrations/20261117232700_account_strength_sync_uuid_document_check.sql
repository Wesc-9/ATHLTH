-- Swift UUID encoding can use uppercase hex, while PostgreSQL uuid::text
-- is canonical lowercase. Normalize document identity when checking matches.
alter table public.account_strength_workout_sync
  drop constraint if exists account_strength_workout_sync_valid_document;
alter table public.account_strength_workout_sync
  add constraint account_strength_workout_sync_valid_document check (
    jsonb_typeof(document) = 'object'
    and lower(document ->> 'id') = workout_id::text
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
  );
