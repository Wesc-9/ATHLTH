-- Do not retain stale private spectator metadata after an iPhone stops
-- refreshing its owner-only session. This only removes expired rows.
select cron.schedule(
    'athlth-purge-expired-private-workout-status',
    '* * * * *',
    $$delete from public.private_active_workout_status
      where expires_at < now();$$
);
