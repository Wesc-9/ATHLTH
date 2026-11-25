-- Universal competition progress workers and RPC permissions.
do $test$
begin
 if not exists(select 1 from cron.job where jobname='athlth-competition-progress-tick' and active) then
   raise exception 'Competition progression monitor missing';
 end if;
 if exists(select 1 from pg_class where relnamespace='private'::regnamespace and relname in ('athlth_shared_event_slots','athlth_shared_event_scores') and
   (not relrowsecurity or has_table_privilege('authenticated',oid,'SELECT') or has_table_privilege('authenticated',oid,'INSERT'))) then
   raise exception 'Shared exercise results bypass access controls';
 end if;
 if has_function_privilege('anon','public.athlth_shared_event_state(uuid)','EXECUTE')
   or has_function_privilege('anon','public.athlth_shared_event_submit(uuid,uuid,numeric,text,uuid)','EXECUTE')
   or has_function_privilege('anon','public.athlth_shared_event_review(uuid,uuid,uuid,boolean)','EXECUTE')
   or has_function_privilege('authenticated','private.athlth_shared_event_tick(uuid)','EXECUTE') then
   raise exception 'Unauthorized competition execution privilege';
 end if;
 if private.athlth_shared_event_gap('month',1)<>interval '1 month' or private.athlth_shared_event_gap('minute',15)<>interval '15 minutes' then
   raise exception 'Incorrect shared exercise intervals';
 end if;
end;$test$;
