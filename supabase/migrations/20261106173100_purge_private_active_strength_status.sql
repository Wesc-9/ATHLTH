-- Stale strength snapshots must be physically removed, not merely
-- hidden in the iPad interface. pg_cron is already installed.
select cron.schedule(
  'athlth-purge-expired-private-strength',
  '* * * * *',
  $$delete from public.private_active_strength_status
    where expires_at < now();$$
);
