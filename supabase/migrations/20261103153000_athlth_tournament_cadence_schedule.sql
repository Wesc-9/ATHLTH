-- Competition schedule: cadence is the time between exercise openings,
-- while completion_hours is each exercise's independent execution window.
-- Round length derives from the total sequence, not a fixed seven-day week.
alter table public.athlth_tournament_match_exercises
 add column if not exists scheduled_at timestamptz;
update public.athlth_tournament_match_exercises
 set scheduled_at=coalesce(scheduled_at,deadline_at-interval '1 day');
alter table public.athlth_tournament_match_exercises
 alter column scheduled_at set not null;

create or replace function private.athlth_tournament_set_match_dates()
returns trigger language plpgsql security definer
set search_path = '' as $$
declare
  v_t public.athlth_tournaments%rowtype;
  v_practices integer;
  v_round_offset integer;
  v_days integer;
  v_round_span interval;
begin
  select * into v_t from public.athlth_tournaments
  where id=new.tournament_id;
  if not found then raise exception 'Tournament not found'; end if;
  v_days := coalesce(v_t.round_days,7);
  select count(*) into v_practices
    from public.athlth_tournament_practice
   where tournament_id=new.tournament_id;
  v_round_span := (greatest(1,v_t.exercise_count)-1)
       * v_t.cadence_days * interval '1 day'
       + v_t.completion_hours * interval '1 hour';
  if new.phase='warmup' then
     -- Warmups are unscored; use the familiar round-duration setting.
     new.scheduled_at := coalesce(new.scheduled_at,
         clock_timestamp() + (new.round_number-1) * v_days * interval '1 day');
     new.deadline_at := coalesce(new.deadline_at,
         new.scheduled_at + v_days * interval '1 day');
  else
     if new.phase='playoff' or
        (new.phase='cup' and new.round_number>1) then
         -- New elimination rounds begin only after previous approvals.
         new.scheduled_at:=coalesce(new.scheduled_at,clock_timestamp());
     else
         new.scheduled_at:=coalesce(new.scheduled_at,
             clock_timestamp() + v_practices * v_days * interval '1 day'
             + (new.round_number-1) * v_round_span);
     end if;
     new.deadline_at:=coalesce(new.deadline_at,
         new.scheduled_at+v_round_span);
  end if;
  return new;
end;
$$;

create or replace function private.athlth_tournament_initialize_exercise_deadlines()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_exercise record;
 v_count integer;
 v_t public.athlth_tournaments%rowtype;
begin
 if new.phase='warmup' or new.away_id is null then return new; end if;
 select count(*) into v_count
 from public.athlth_tournament_exercise_candidates
 where tournament_id=new.tournament_id and selected_position is not null;
 if v_count=0 then return new; end if;
 select * into v_t from public.athlth_tournaments where id=new.tournament_id;
 for v_exercise in
   select id,selected_position
   from public.athlth_tournament_exercise_candidates
   where tournament_id=new.tournament_id and selected_position is not null
   order by selected_position
 loop
   insert into public.athlth_tournament_match_exercises(
      tournament_id,match_id,candidate_id,position,scheduled_at,deadline_at
   ) values (
      new.tournament_id,new.id,v_exercise.id,v_exercise.selected_position,
      new.scheduled_at+
        (v_exercise.selected_position-1)*v_t.cadence_days * interval '1 day',
      new.scheduled_at+
        (v_exercise.selected_position-1)*v_t.cadence_days * interval '1 day'
        + v_t.completion_hours * interval '1 hour'
   );
 end loop;
 return new;
end;
$$;
create or replace function private.athlth_tournament_retime_exercises()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 v_count integer;
begin
 if new.deadline_at is not distinct from old.deadline_at then return new; end if;
 select count(*) into v_count from public.athlth_tournament_match_exercises
  where match_id=new.id;
 -- Preserve individually negotiated cutoffs. Extending the match
 -- only extends the last still-pending exercise, not all earlier slots.
 update public.athlth_tournament_match_exercises e
 set deadline_at=new.deadline_at
 where e.match_id=new.id and e.state='pending'
   and e.position=(select max(position)
                   from public.athlth_tournament_match_exercises
                   where match_id=new.id);
 return new;
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
     case when p_source_workout is not null then 'approved' else 'submitted' end,
     case when p_source_workout is not null then now() else null end
 )
 on conflict(match_exercise_id,user_id) do nothing;
end;
$$;


revoke all on function private.athlth_tournament_set_match_dates(),
 private.athlth_tournament_initialize_exercise_deadlines(),
 private.athlth_tournament_retime_exercises() from public,anon,authenticated;
revoke all on function public.athlth_tournament_complete_exercise(uuid,text,uuid) from public,anon;
grant execute on function public.athlth_tournament_complete_exercise(uuid,text,uuid) to authenticated;
