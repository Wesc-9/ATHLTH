-- Server-owned completion evidence; unreviewed self-reports cannot
-- trigger automatic walkovers. Approved ATHLTH workouts may be accepted
-- only if the same athlete recorded the source workout within the window.
alter table public.athlth_tournament_exercise_completions
 add column if not exists review_status text not null default 'submitted'
   check (review_status in ('submitted','approved','disputed')),
 add column if not exists approved_by uuid references public.profiles(id),
 add column if not exists approved_at timestamptz;

create or replace function public.athlth_tournament_review_exercise(
 p_match_exercise uuid,p_athlete uuid,p_approve boolean
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_slot public.athlth_tournament_match_exercises%rowtype;
 v_match public.athlth_tournament_matches%rowtype;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_slot from public.athlth_tournament_match_exercises
   where id=p_match_exercise for update;
 if not found then raise exception 'Exercise not found'; end if;
 select * into v_match from public.athlth_tournament_matches
   where id=v_slot.match_id for update;
 if v_slot.state<>'pending' or
    not private.athlth_tournament_is_accepted(v_slot.tournament_id) or
    p_athlete not in (v_match.home_id,v_match.away_id) or
    v_user not in (v_match.home_id,v_match.away_id) or
    v_user=p_athlete then
   raise exception 'Only the other competing athlete can review completion';
 end if;
 update public.athlth_tournament_exercise_completions
    set review_status=case when p_approve then 'approved' else 'disputed' end,
        approved_by=case when p_approve then v_user else null end,
        approved_at=case when p_approve then now() else null end
  where match_exercise_id=p_match_exercise and user_id=p_athlete
    and review_status='submitted';
 if not found then raise exception 'No pending workout proof to review'; end if;
 if not p_approve then
   update public.athlth_tournament_match_exercises
     set state='disputed',resolved_at=now() where id=p_match_exercise;
   update public.athlth_tournament_matches
     set status='disputed' where id=v_match.id and status='scheduled';
 end if;
 insert into public.athlth_tournament_audit(
    tournament_id,actor_id,event,info
 ) values(v_slot.tournament_id,v_user,
     case when p_approve then 'exercise_proof_approved'
          else 'exercise_proof_disputed' end,
     jsonb_build_object('slot',p_match_exercise,'athlete',p_athlete));
end;
$$;

create or replace function public.athlth_tournament_complete_exercise(
 p_match_exercise uuid,p_evidence_note text,p_source_workout uuid default null
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_ex public.athlth_tournament_match_exercises%rowtype;
 v_match public.athlth_tournament_matches%rowtype;
 v_state text;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_ex from public.athlth_tournament_match_exercises
 where id=p_match_exercise for update;
 if not found or v_ex.state<>'pending' or now()>v_ex.deadline_at then
   raise exception 'Exercise deadline has passed';
 end if;
 select * into v_match from public.athlth_tournament_matches
 where id=v_ex.match_id;
 select status into v_state from public.athlth_tournaments
 where id=v_ex.tournament_id;
 if v_state<>'active' or v_match.status='confirmed' or
    v_user not in (v_match.home_id,v_match.away_id) or
    not private.athlth_tournament_is_accepted(v_ex.tournament_id) then
   raise exception 'This exercise is not open to this athlete';
 end if;
 if v_match.scheduled_at>now() then
   raise exception 'Exercise has not started';
 end if;
 if p_evidence_note is null or
    length(btrim(p_evidence_note)) not between 3 and 500 then
   raise exception 'Provide a short description of the completed workout';
 end if;
 if p_source_workout is not null and not exists(
    select 1 from public.social_challenge_attempts a
    where a.user_id=v_user
      and a.source_workout_id=p_source_workout
      and a.verification='athlth'
      and a.is_eligible=true
      and a.ended_at<=v_ex.deadline_at
      and a.started_at>=v_match.scheduled_at
 ) then
   raise exception 'Workout could not be verified for this exercise window';
 end if;
 insert into public.athlth_tournament_exercise_completions(
    match_exercise_id,user_id,source_workout_id,evidence_note,
    review_status,approved_at
 ) values(p_match_exercise,v_user,p_source_workout,btrim(p_evidence_note),
     case when p_source_workout is not null then 'approved' else 'submitted' end,
     case when p_source_workout is not null then now() else null end
 )
 on conflict(match_exercise_id,user_id) do nothing;
end;
$$;

create or replace function private.athlth_tournament_process_exercise_deadlines()
returns integer language plpgsql security definer set search_path='' as $$
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
$$;

revoke all on function public.athlth_tournament_review_exercise(uuid,uuid,boolean)
 from public,anon;
grant execute on function public.athlth_tournament_review_exercise(uuid,uuid,boolean)
 to authenticated;
