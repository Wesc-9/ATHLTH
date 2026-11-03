-- Sport-safe proof: the generic challenge attempt table cannot prove
-- that a workout belongs to this tournament's selected modality/preset.
-- Until sport-aware HealthKit verification is integrated, even a verified
-- source workout must be independently approved by the opponent.
-- This avoids awarding a cycling walkover from a running record.
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
 if v_ex.scheduled_at>now() then
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
     'submitted',null
 )
 on conflict(match_exercise_id,user_id) do nothing;
end;
$$;



revoke all on function public.athlth_tournament_complete_exercise(uuid,text,uuid)
 from public,anon;
grant execute on function public.athlth_tournament_complete_exercise(uuid,text,uuid)
 to authenticated;
