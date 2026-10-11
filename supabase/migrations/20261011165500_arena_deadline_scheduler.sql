-- Backend-only deadline reconciliation, every 15 minutes. Uses the same
-- idempotent, locked finalizer as the explicit in-app refresh.
create extension if not exists pg_cron with schema pg_catalog;
do $$
begin
  if not exists (
    select 1 from cron.job
    where jobname='athlth-arena-complete-due-series'
  ) then
    perform cron.schedule(
      'athlth-arena-complete-due-series',
      '*/15 * * * *',
      'select private.arena_finalize_due_all();'
    );
  end if;
end $$;
