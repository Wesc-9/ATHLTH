-- Regression coverage for the shared roster rule and duel guard.
do $test$
begin
 if private.athlth_competition_minimum_athletes('league',true,'{"duelMode":true}'::jsonb)<>2
 or private.athlth_competition_minimum_athletes('league',true,'{}'::jsonb)<>3
 or private.athlth_competition_minimum_athletes('league',false,'{}'::jsonb)<>2
 or private.athlth_competition_minimum_athletes('cup',false,'{}'::jsonb)<>4 then
   raise exception 'Unexpected competition roster minimum';
 end if;
 if not exists (select 1 from pg_trigger where tgname='athlth_duel_no_extra_entrants'
      and tgrelid='public.athlth_tournament_entries'::regclass and tgenabled<>'D') then
   raise exception 'Duel roster guard missing';
 end if;
end;
$test$;