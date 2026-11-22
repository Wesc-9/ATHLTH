CREATE OR REPLACE FUNCTION private.athlth_tournament_process_exercise_deadlines()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_slot record;
 v_match public.athlth_tournament_matches%rowtype;
 v_home boolean;
 v_away boolean;
 v_loser uuid;
 v_count integer:=0;
begin
 for v_slot in
   select e.id,e.match_id,e.tournament_id,e.deadline_at
   from public.athlth_tournament_match_exercises e
   join public.athlth_tournaments t on t.id=e.tournament_id
   where e.state='pending' and e.deadline_at<=clock_timestamp()
     and t.status='active'
     and not t.competition_settings_applied
   order by e.deadline_at,e.id
   for update of e skip locked
 loop
   select * into v_match from public.athlth_tournament_matches
    where id=v_slot.match_id for update;
   if not found or v_match.status='confirmed' then
     update public.athlth_tournament_match_exercises
       set state='completed',resolved_at=now() where id=v_slot.id;
     continue;
   end if;
   select exists(select 1 from public.athlth_tournament_exercise_completions
      where match_exercise_id=v_slot.id and user_id=v_match.home_id and review_status='approved')
     into v_home;
   select exists(select 1 from public.athlth_tournament_exercise_completions
      where match_exercise_id=v_slot.id and user_id=v_match.away_id and review_status='approved')
     into v_away;
   if v_home and v_away then
     update public.athlth_tournament_match_exercises
       set state='completed',resolved_at=now() where id=v_slot.id;
   elsif v_home<>v_away and not exists(
       select 1 from public.athlth_tournament_exercise_completions a
       where a.match_exercise_id=v_slot.id and a.review_status='submitted'
   ) then
     v_loser:=case when v_home then v_match.away_id else v_match.home_id end;
     update public.athlth_tournament_match_exercises
       set state='walkover',winner_id=case when v_home
             then v_match.home_id else v_match.away_id end,
           resolved_at=now() where id=v_slot.id;
     update public.athlth_tournament_matches
       set status='confirmed',
           home_score=case when v_home then 1 else 0 end,
           away_score=case when v_away then 1 else 0 end,
           walkover_loser_id=v_loser,
           walkover_reason='exercise_deadline_missed',
           evidence_note='Walkover: missed exercise completion deadline',
           confirmed_at=now(),confirmed_by=null,proposed_by=null
       where id=v_match.id;
     insert into public.athlth_tournament_audit(tournament_id,event,info)
       values(v_slot.tournament_id,'exercise_walkover',
        jsonb_build_object('match',v_match.id,'exercise_slot',v_slot.id,
                           'winner',case when v_home then v_match.home_id
                                         else v_match.away_id end,
                           'loser',v_loser,'deadline',v_slot.deadline_at));
     perform private.athlth_tournament_advance(v_slot.tournament_id);
     v_count:=v_count+1;
   else
     -- Both absent: cannot arbitrarily decide an elimination winner.
     update public.athlth_tournament_match_exercises
       set state='disputed',resolved_at=now() where id=v_slot.id;
     update public.athlth_tournament_matches set status='disputed'
       where id=v_match.id and status='scheduled';
     insert into public.athlth_tournament_audit(tournament_id,event,info)
       values(v_slot.tournament_id,'both_missed_exercise',
        jsonb_build_object('match',v_match.id,'exercise_slot',v_slot.id));
   end if;
 end loop;
 return v_count;
end;
$function$
