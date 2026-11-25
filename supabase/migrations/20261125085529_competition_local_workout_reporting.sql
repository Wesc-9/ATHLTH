
-- Client measurements are explicitly local evidence, not sensor attestation.
-- Reuse the existing exercise submission/review paths for all formats.
create table private.athlth_competition_local_measurements (
 tournament_id uuid not null,
 user_id uuid not null,
 workout_id uuid not null,
 measurement_key text not null,
 target_id uuid not null,
 primary key(tournament_id,user_id,workout_id,measurement_key),
 foreign key(tournament_id,user_id) references public.athlth_tournament_entries(tournament_id,user_id) on delete cascade
);
alter table private.athlth_competition_local_measurements enable row level security;
revoke all on private.athlth_competition_local_measurements from public,anon,authenticated;

create or replace function public.athlth_competition_local_targets(p_tournament uuid,p_user uuid)
returns table(target_id uuid,candidate_id uuid,library_exercise_id uuid,activity text,metric text,target_value numeric,opens_at timestamptz,deadline_at timestamptz,progress text)
language plpgsql stable security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype;
begin
 if auth.uid() is null or auth.uid() is distinct from p_user or not private.athlth_tournament_is_accepted(p_tournament) then
   raise exception 'Not an eligible participant';
 end if;
 select * into t from public.athlth_tournaments where id=p_tournament;
 if not found or t.status<>'active' or t.proof_mode<>'opponent' or t.required_environment<>'any'
   or t.race_rules->>'discipline' is distinct from 'workout'
   or coalesce(t.race_rules->>'recordingDevice','any')<>'any'
   or nullif(t.race_rules->>'competitionEndsAt','')::timestamptz<=clock_timestamp()
 then return; end if;
 if t.single_event_mode then
   if t.race_rules->>'exerciseScoringVersion' is distinct from '2' then return; end if;
   return query select s.candidate_id,s.candidate_id,c.exercise_id,d.activity,d.metric,d.target_value,s.opens_at,s.deadline_at,coalesce(r.state,'pending')
   from private.athlth_shared_event_slots s
   join private.athlth_single_event_exercise_definitions(t.id) d on d.candidate_id=s.candidate_id
   join public.athlth_tournament_exercise_candidates c on c.id=s.candidate_id
   left join private.athlth_shared_event_scores r on r.tournament_id=t.id and r.candidate_id=s.candidate_id and r.user_id=p_user
   where s.tournament_id=t.id and s.opens_at<=clock_timestamp() and s.deadline_at>clock_timestamp();
 else
   return query select s.id,s.candidate_id,c.exercise_id,d.activity,d.metric,d.target_value,s.scheduled_at,s.deadline_at,coalesce(r.review_status,'pending')
   from public.athlth_tournament_match_exercises s
   join public.athlth_tournament_matches m on m.id=s.match_id
   join private.athlth_single_event_exercise_definitions(t.id) d on d.candidate_id=s.candidate_id
   join public.athlth_tournament_exercise_candidates c on c.id=s.candidate_id
   left join public.athlth_tournament_exercise_completions r on r.match_exercise_id=s.id and r.user_id=p_user
   where s.tournament_id=t.id and m.phase<>'warmup' and m.away_id is not null and p_user in (m.home_id,m.away_id)
     and m.status in ('scheduled','disputed') and s.state='pending'
     and s.scheduled_at<=clock_timestamp() and s.deadline_at>clock_timestamp();
 end if;
end;$fn$;
revoke all on function public.athlth_competition_local_targets(uuid,uuid) from public,anon,authenticated;
grant execute on function public.athlth_competition_local_targets(uuid,uuid) to authenticated;

create or replace function public.athlth_competition_submit_local_measurement(
 p_tournament uuid,p_user uuid,p_target uuid,p_workout uuid,p_score numeric,p_started timestamptz,p_ended timestamptz)
returns boolean language plpgsql security definer set search_path='' as $fn$
declare d record; is_single boolean; measurement_key text; unit_label text; note text;
begin
 if auth.uid() is null or auth.uid() is distinct from p_user or p_workout is null then raise exception 'Not authorized'; end if;
 -- The existing submission RPCs recheck membership and deadlines under lock.
 select * into d from public.athlth_competition_local_targets(p_tournament,p_user) x where x.target_id=p_target;
 if not found or d.progress<>'pending' then return false; end if;
 if p_started is null or p_ended is null or p_started<d.opens_at or p_ended>d.deadline_at or p_ended>clock_timestamp() or p_ended<=p_started
   or p_score is null or p_score not between 0 and 100000000
   or (d.metric='distance' and p_score<=0)
   or (d.metric='repetitions' and trunc(p_score)<>p_score)
 then raise exception 'Invalid local measurement'; end if;
 if d.activity in ('running','walking') and d.metric in ('distance','duration') and d.target_value is not null then
   measurement_key:='cardio:'||d.activity;
 elsif d.activity='strength' and d.library_exercise_id is not null and d.metric in ('repetitions','time') then
   measurement_key:='strength:'||d.library_exercise_id::text;
 else raise exception 'Exercise requires manual reporting'; end if;
 insert into private.athlth_competition_local_measurements(tournament_id,user_id,workout_id,measurement_key,target_id)
 values(p_tournament,p_user,p_workout,measurement_key,p_target) on conflict do nothing;
 if not found then return false; end if;
 unit_label:=case d.metric when 'distance' then 'sek' when 'duration' then 'm' when 'time' then 'sek' else 'repetisjoner' end;
 note:='Automatisk innsending fra lokal treningsregistrering (ikke serververifisert): '||p_score::text||' '||unit_label;
 select single_event_mode into is_single from public.athlth_tournaments where id=p_tournament;
 if is_single then
   perform public.athlth_shared_event_submit(p_tournament,d.candidate_id,p_score,note,null);
 else
   perform public.athlth_tournament_complete_exercise(p_target,note,null);
 end if;
 return true;
end;$fn$;
revoke all on function public.athlth_competition_submit_local_measurement(uuid,uuid,uuid,uuid,numeric,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.athlth_competition_submit_local_measurement(uuid,uuid,uuid,uuid,numeric,timestamptz,timestamptz) to authenticated;
