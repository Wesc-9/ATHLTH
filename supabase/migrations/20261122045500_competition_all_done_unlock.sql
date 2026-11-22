create or replace function private.athlth_competition_unlock_next()
returns integer language plpgsql security definer set search_path='' as $fn$
declare v_slot record; v_count integer:=0;
begin
 for v_slot in
   select s.id,s.tournament_id,s.position,
          m.phase,m.round_number,m.group_index,t.completion_hours
   from public.athlth_tournament_match_exercises s
   join public.athlth_tournament_matches m on m.id=s.match_id
   join public.athlth_tournaments t on t.id=s.tournament_id
   where t.status='active' and t.competition_settings_applied
     and t.release_mode='everyone_finished'
     and s.state='pending' and s.position>1
     and s.scheduled_at>=timestamptz '2099-01-01'
   order by s.tournament_id,s.position
   for update of s skip locked
 loop
   if not exists (
     select 1
     from public.athlth_tournament_match_exercises prior
     join public.athlth_tournament_matches pm
       on pm.id=prior.match_id
     where prior.tournament_id=v_slot.tournament_id
       and pm.phase=v_slot.phase and pm.round_number=v_slot.round_number
       and pm.group_index is not distinct from v_slot.group_index
       and prior.position=v_slot.position-1
       and prior.state='pending'
       and not (
         exists(select 1
          from public.athlth_tournament_exercise_completions c
          where c.match_exercise_id=prior.id and c.user_id=pm.home_id
            and c.review_status='approved')
         and exists(select 1
          from public.athlth_tournament_exercise_completions c
          where c.match_exercise_id=prior.id and c.user_id=pm.away_id
            and c.review_status='approved')
       )
   ) then
     update public.athlth_tournament_match_exercises
       set scheduled_at=clock_timestamp(),
           deadline_at=clock_timestamp()+
               v_slot.completion_hours*interval '1 hour'
     where id=v_slot.id and scheduled_at>=timestamptz '2099-01-01';
     if found then v_count:=v_count+1; end if;
   end if;
 end loop;
 return v_count;
end;
$fn$;
revoke all on function private.athlth_competition_unlock_next()
from public,anon,authenticated;
do $s$
begin
 if not exists(
    select 1 from cron.job
    where jobname='athlth-competition-unlock-next'
 ) then
    perform cron.schedule(
       'athlth-competition-unlock-next','*/5 * * * *',
       'select private.athlth_competition_unlock_next();'
    );
 end if;
end;
$s$;