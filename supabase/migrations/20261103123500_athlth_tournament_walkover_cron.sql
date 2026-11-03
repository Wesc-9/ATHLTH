-- Server-side processing is independent of whether anyone keeps the app
-- open. Idempotent and lock-protected; a second run cannot create duplicate WOs.
do $$
begin
 if not exists (
   select 1 from cron.job where jobname='athlth-tournament-exercise-deadlines'
 ) then
   perform cron.schedule(
      'athlth-tournament-exercise-deadlines',
      '*/5 * * * *',
      'select private.athlth_tournament_process_exercise_deadlines();'
   );
 end if;
end;
$$;
