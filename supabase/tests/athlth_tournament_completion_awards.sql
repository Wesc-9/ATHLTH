-- Non-mutating verification of automatic Arena podium awards.
do $$
declare
 v_trigger integer;
begin
 select count(*) into v_trigger
 from pg_trigger
 where tgrelid='public.athlth_tournaments'::regclass
 and tgname='athlth_tournament_completed_awards'
 and tgenabled<>'D';
 if v_trigger<>1 then
   raise exception 'Arena podium trigger is missing';
 end if;
 if has_function_privilege('anon',
   'private.athlth_tournament_grant_completed_awards()','EXECUTE')
   or has_function_privilege('authenticated',
   'private.athlth_tournament_grant_completed_awards()','EXECUTE') then
   raise exception 'Award trigger should not be callable from clients';
 end if;
 if not exists (
    select 1 from pg_constraint where conrelid='public.athlth_award_unlocks'::regclass
     and contype='p'
 ) then raise exception 'Unlocks must be uniquely keyed'; end if;
 if not exists (
    select 1 from pg_proc where pronamespace='private'::regnamespace
     and proname='athlth_tournament_grant_completed_awards'
 ) then raise exception 'Awarding procedure missing'; end if;
end;
$$;
