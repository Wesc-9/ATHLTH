-- ATHLTH Arena 2.0.9: non-mutating security and readiness smoke checks.
do $$
declare
 v_table text;
 v_policy_count integer;
begin
 foreach v_table in array array[
  'athlth_tournament_exercise_candidates',
  'athlth_tournament_exercise_votes',
  'athlth_tournament_lobby_messages',
  'athlth_tournament_player_change',
  'athlth_tournament_player_change_votes',
  'athlth_tournament_match_exercises',
  'athlth_tournament_exercise_completions'
 ] loop
    if not (select relrowsecurity from pg_class
      where oid=('public.'||v_table)::regclass) then
       raise exception 'RLS disabled on %',v_table;
    end if;
    if has_table_privilege('anon',('public.'||v_table)::regclass,'SELECT')
       or has_table_privilege('authenticated',('public.'||v_table)::regclass,'INSERT')
       or has_table_privilege('authenticated',('public.'||v_table)::regclass,'UPDATE')
       or has_table_privilege('authenticated',('public.'||v_table)::regclass,'DELETE') then
      raise exception 'Direct lobby table write/read privilege leaked on %',v_table;
    end if;
    select count(*) into v_policy_count from pg_policies
       where schemaname='public' and tablename=v_table
         and cmd='SELECT';
    if v_policy_count<1 then
      raise exception 'No SELECT RLS policy on %',v_table;
    end if;
 end loop;
 if has_function_privilege('anon',
    'public.athlth_tournament_vote_exercise(uuid,boolean)','EXECUTE') then
    raise exception 'Vote RPC available to anonymous users';
 end if;
 if has_function_privilege('anon',
    'public.athlth_tournament_forfeit_player(uuid,uuid)','EXECUTE') then
    raise exception 'Walkover RPC available to anonymous users';
 end if;
 if has_function_privilege('anon',
    'public.athlth_tournament_review_exercise(uuid,uuid,boolean)','EXECUTE') then
    raise exception 'Proof review RPC available to anonymous users';
 end if;
 if has_function_privilege('authenticated',
    'private.athlth_tournament_process_exercise_deadlines()','EXECUTE') then
    raise exception 'Internal deadline worker exposed to athletes';
 end if;
 if not exists(select 1 from cron.job
    where jobname='athlth-tournament-exercise-deadlines' and active) then
    raise exception 'Deadline monitor not scheduled';
 end if;
 if not exists(select 1 from cron.job
    where jobname='athlth-tournament-vote-finalization' and active) then
    raise exception 'Ballot finalizer not scheduled';
 end if;
 if not exists(select 1 from pg_trigger where tgname='athlth_tournament_match_exercises_insert'
        and tgenabled<>'D') then
    raise exception 'Exercise deadline trigger missing';
 end if;
end;
$$;
