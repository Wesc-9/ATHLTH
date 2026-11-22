create or replace function private.athlth_competition_process_exercise_deadlines()
returns integer language plpgsql security definer set search_path='' as $fn$
declare v_slot record;
 v_match public.athlth_tournament_matches%rowtype;
 v_home boolean;v_away boolean;v_submitted boolean;
 v_home_points integer;v_away_points integer;v_remaining integer;
 v_count integer:=0;
begin
 for v_slot in
   select e.id,e.match_id,e.tournament_id,e.deadline_at
   from public.athlth_tournament_match_exercises e
   join public.athlth_tournaments t on t.id=e.tournament_id
   where e.state='pending' and e.deadline_at<=clock_timestamp()
     and t.status='active' and t.competition_settings_applied
   order by e.deadline_at,e.id
   for update of e skip locked
 loop
   select * into v_match from public.athlth_tournament_matches
   where id=v_slot.match_id for update;
   if not found or v_match.status='confirmed' then
     update public.athlth_tournament_match_exercises
     set state='completed',resolved_at=clock_timestamp()
     where id=v_slot.id;
     continue;
   end if;
   if v_match.status='proposed' then continue; end if;
   select exists(
       select 1 from public.athlth_tournament_exercise_completions c
       where c.match_exercise_id=v_slot.id
         and c.user_id=v_match.home_id and c.review_status='approved'
   ) into v_home;
   select exists(
       select 1 from public.athlth_tournament_exercise_completions c
       where c.match_exercise_id=v_slot.id
         and c.user_id=v_match.away_id and c.review_status='approved'
   ) into v_away;
   select exists(
       select 1 from public.athlth_tournament_exercise_completions c
       where c.match_exercise_id=v_slot.id and c.review_status='submitted'
   ) into v_submitted;
   if v_submitted and not (v_home and v_away) then
     -- An on-time submission under review must not be scored zero.
     continue;
   end if;
   update public.athlth_tournament_match_exercises
     set state=case
            when v_home and v_away then 'completed'
            when v_home or v_away then 'walkover'
            else 'disputed' end,
         winner_id=case when v_home and not v_away
                 then v_match.home_id
                 when v_away and not v_home then v_match.away_id
                 else null end,
         resolved_at=clock_timestamp()
   where id=v_slot.id;
   insert into public.athlth_tournament_audit(tournament_id,event,info)
   values(v_slot.tournament_id,'competition_exercise_scored',
      jsonb_build_object('slot',v_slot.id,
          'home_points',case when v_home then 1 else 0 end,
          'away_points',case when v_away then 1 else 0 end,
          'deadline',v_slot.deadline_at));
   select count(*) into v_remaining
   from public.athlth_tournament_match_exercises ex
   where ex.match_id=v_match.id and ex.state='pending';
   if v_remaining>0 then continue; end if;
   select count(*) into v_home_points
   from public.athlth_tournament_match_exercises ex
   join public.athlth_tournament_exercise_completions c
     on c.match_exercise_id=ex.id
   where ex.match_id=v_match.id and c.user_id=v_match.home_id
     and c.review_status='approved';
   select count(*) into v_away_points
   from public.athlth_tournament_match_exercises ex
   join public.athlth_tournament_exercise_completions c
     on c.match_exercise_id=ex.id
   where ex.match_id=v_match.id and c.user_id=v_match.away_id
     and c.review_status='approved';
   if v_home_points=v_away_points and
      (v_match.phase in ('cup','playoff') or v_home_points=0) then
     update public.athlth_tournament_matches
       set status='disputed',home_score=v_home_points,
           away_score=v_away_points
     where id=v_match.id and status='scheduled';
     -- No random winner if both athletes miss or a cup is tied.
   else
     update public.athlth_tournament_matches
       set status='confirmed',home_score=v_home_points,
           away_score=v_away_points,confirmed_at=clock_timestamp(),
           proposed_by=null,confirmed_by=null,
           evidence_note='Approved exercise results and zero for missed deadlines'
     where id=v_match.id and status='scheduled';
     if found then
       perform private.athlth_tournament_advance(v_slot.tournament_id);
     end if;
   end if;
   v_count:=v_count+1;
 end loop;
 return v_count;
end;
$fn$;
revoke all on function private.athlth_competition_process_exercise_deadlines()
from public,anon,authenticated;
do $s$
begin
 if not exists(select 1 from cron.job
   where jobname='athlth-competition-exercise-deadlines') then
   perform cron.schedule(
      'athlth-competition-exercise-deadlines','*/5 * * * *',
      'select private.athlth_competition_process_exercise_deadlines();'
   );
 end if;
end;
$s$;