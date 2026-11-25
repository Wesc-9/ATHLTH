
-- Shared exercise deadlines and incremental submissions, with equal-weight
-- ranking across exercises. V2 is opt-in; existing scalar RPCs cannot bypass it.
create table if not exists private.athlth_shared_event_slots (
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 candidate_id uuid not null references public.athlth_tournament_exercise_candidates(id) on delete cascade,
 sort_order integer not null,
 opens_at timestamptz,
 deadline_at timestamptz,
 closed_at timestamptz,
 primary key(tournament_id,candidate_id)
);
create table if not exists private.athlth_shared_event_scores (
 tournament_id uuid not null,
 candidate_id uuid not null,
 user_id uuid not null,
 score numeric,
 evidence_note text,
 source_workout_id uuid,
 state text not null check(state in ('submitted','approved','rejected','missed')),
 submitted_at timestamptz,
 primary key(tournament_id,candidate_id,user_id),
 foreign key(tournament_id,candidate_id) references private.athlth_shared_event_slots(tournament_id,candidate_id) on delete cascade,
 foreign key(tournament_id,user_id) references public.athlth_tournament_entries(tournament_id,user_id) on delete cascade
);
alter table private.athlth_shared_event_slots enable row level security;
alter table private.athlth_shared_event_scores enable row level security;
revoke all on private.athlth_shared_event_slots,private.athlth_shared_event_scores from public,anon,authenticated;
create unique index if not exists athlth_shared_event_no_workout_reuse
 on private.athlth_shared_event_scores(tournament_id,user_id,source_workout_id) where source_workout_id is not null;

create or replace function private.athlth_shared_event_gap(p_unit text,p_every integer)
returns interval language sql immutable set search_path='' as $fn$
 select case p_unit when 'minute' then make_interval(mins=>p_every)
 when 'hour' then make_interval(hours=>p_every) when 'day' then make_interval(days=>p_every)
 else make_interval(months=>p_every) end
$fn$;

create or replace function private.athlth_shared_event_initialize()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare cap timestamptz:=nullif(new.race_rules->>'competitionEndsAt','')::timestamptz;
begin
 if new.status='active' and old.status is distinct from new.status and new.single_event_mode
    and new.race_rules->>'exerciseScoringVersion'='2' then
   insert into private.athlth_shared_event_slots(tournament_id,candidate_id,sort_order,opens_at,deadline_at)
   select new.id,d.candidate_id,d.sort_order,
      case when new.release_mode='interval' or d.sort_order=1
           then new.race_signal_at+(d.sort_order-1)*private.athlth_shared_event_gap(new.release_unit,new.release_every) end,
      case when new.release_mode='interval' or d.sort_order=1
           then least(cap,new.race_signal_at+(d.sort_order-1)*private.athlth_shared_event_gap(new.release_unit,new.release_every)+make_interval(hours=>new.completion_hours)) end
   from private.athlth_single_event_exercise_definitions(new.id) d;
 end if;
 return new;
end;$fn$;
revoke all on function private.athlth_shared_event_initialize() from public,anon,authenticated;
drop trigger if exists athlth_shared_event_initialize on public.athlth_tournaments;
create trigger athlth_shared_event_initialize after update of status on public.athlth_tournaments
 for each row execute function private.athlth_shared_event_initialize();

create or replace function private.athlth_shared_event_tick(p_tournament uuid)
returns void language plpgsql security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; slot record; current_time_at timestamptz:=clock_timestamp(); cap timestamptz; athlete_count integer;
begin
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or t.status<>'active' or not t.single_event_mode or t.race_rules->>'exerciseScoringVersion' is distinct from '2' then return; end if;
 cap:=nullif(t.race_rules->>'competitionEndsAt','')::timestamptz;
 for slot in select s.* from private.athlth_shared_event_slots s where s.tournament_id=t.id and s.closed_at is null order by s.sort_order loop
   if slot.opens_at is null and (cap<=current_time_at or not exists(
      select 1 from private.athlth_shared_event_slots prior where prior.tournament_id=t.id and prior.sort_order<slot.sort_order and prior.closed_at is null)) then
     slot.opens_at:=current_time_at;
     slot.deadline_at:=least(cap,current_time_at+make_interval(hours=>t.completion_hours));
     update private.athlth_shared_event_slots s set opens_at=slot.opens_at,deadline_at=slot.deadline_at
       where s.tournament_id=t.id and s.candidate_id=slot.candidate_id;
   end if;
   if slot.deadline_at<=current_time_at or cap<=current_time_at then
     insert into private.athlth_shared_event_scores(tournament_id,candidate_id,user_id,state)
     select t.id,slot.candidate_id,e.user_id,'missed' from public.athlth_tournament_entries e
      where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
     on conflict(tournament_id,candidate_id,user_id) do update set state='missed',score=null,evidence_note=null,source_workout_id=null
        where private.athlth_shared_event_scores.state='rejected';
   end if;
   if not exists(select 1 from public.athlth_tournament_entries e where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
       and not exists(select 1 from private.athlth_shared_event_scores r where r.tournament_id=t.id and r.candidate_id=slot.candidate_id and r.user_id=e.user_id and r.state in ('approved','missed'))) then
     update private.athlth_shared_event_slots s set closed_at=current_time_at where s.tournament_id=t.id and s.candidate_id=slot.candidate_id;
   end if;
 end loop;
 if not exists(select 1 from private.athlth_shared_event_slots s where s.tournament_id=t.id and s.closed_at is null)
    and exists(select 1 from private.athlth_shared_event_slots s where s.tournament_id=t.id) then
   select count(*) into athlete_count from public.athlth_tournament_entries e where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null;
   if not exists(select 1 from private.athlth_shared_event_scores r where r.tournament_id=t.id and r.state='approved') then
      update public.athlth_tournaments set status='cancelled',completed_at=current_time_at where id=t.id;
   else
      with ranks as (
       select r.user_id,r.candidate_id,r.score,rank() over(partition by r.candidate_id order by
         case when d.metric='distance' then r.score end asc nulls last,
         case when d.metric<>'distance' then r.score end desc nulls last) as place
       from private.athlth_shared_event_scores r
       join private.athlth_single_event_exercise_definitions(t.id) d on d.candidate_id=r.candidate_id
       join public.athlth_tournament_entries e on e.tournament_id=r.tournament_id and e.user_id=r.user_id
       where r.tournament_id=t.id and r.state='approved' and e.response='accepted' and e.removed_at is null
      ), totals as (
       select user_id,sum(athlete_count-place+1) as points,jsonb_object_agg(candidate_id::text,score) as scores
       from ranks group by user_id
      )
      insert into public.athlth_tournament_single_event_results(tournament_id,user_id,reported_score,evidence_note,exercise_scores,review_status,submitted_at)
      select t.id,e.user_id,coalesce(x.points,0),'Individuelle øvelsesresultater',coalesce(x.scores,'{}'::jsonb),'approved',current_time_at
      from public.athlth_tournament_entries e left join totals x on x.user_id=e.user_id
      where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
      on conflict(tournament_id,user_id) do nothing;
      update public.athlth_tournaments set status='completed',completed_at=current_time_at where id=t.id;
   end if;
   insert into public.athlth_tournament_audit(tournament_id,actor_id,event) values(t.id,t.owner_id,'single_event_exercises_closed');
 end if;
end;$fn$;
revoke all on function private.athlth_shared_event_tick(uuid) from public,anon,authenticated;

create or replace function public.athlth_shared_event_state(p_tournament uuid)
returns table(candidate_id uuid,title text,metric text,target_value numeric,activity text,sort_order integer,opens_at timestamptz,deadline_at timestamptz,user_id uuid,progress text,score numeric,evidence_note text)
language plpgsql stable security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament;
 if not found or not t.single_event_mode or t.race_rules->>'exerciseScoringVersion' is distinct from '2'
    or not private.athlth_tournament_can_view(t.id) then raise exception 'Competition not accessible'; end if;
 return query select d.candidate_id,d.title,d.metric,d.target_value,d.activity,d.sort_order,
  s.opens_at,s.deadline_at,e.user_id,coalesce(r.state,'pending'),
  case when visible.ok then r.score end,case when visible.ok and t.status<>'completed' then r.evidence_note end
 from private.athlth_single_event_exercise_definitions(t.id) d
 left join private.athlth_shared_event_slots s on s.tournament_id=t.id and s.candidate_id=d.candidate_id
 cross join public.athlth_tournament_entries e
 left join private.athlth_shared_event_scores r on r.tournament_id=t.id and r.candidate_id=d.candidate_id and r.user_id=e.user_id
 cross join lateral (select (e.user_id=actor or t.status='completed' and r.state='approved'
   or (t.race_rules->>'duelMode' is distinct from 'true' and t.owner_id=actor)
   or (t.race_rules->>'duelMode'='true' and exists(select 1 from private.athlth_shared_event_scores own
      where own.tournament_id=t.id and own.candidate_id=d.candidate_id and own.user_id=actor and own.state in ('submitted','approved','missed')))) ok) visible
 where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null order by d.sort_order,e.seed;
end;$fn$;
revoke all on function public.athlth_shared_event_state(uuid) from public,anon,authenticated;
grant execute on function public.athlth_shared_event_state(uuid) to authenticated;

create or replace function public.athlth_shared_event_submit(p_tournament uuid,p_candidate uuid,p_score numeric,p_evidence text,p_source_workout uuid default null)
returns void language plpgsql security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; s private.athlth_shared_event_slots%rowtype; d record; a record; actor uuid:=auth.uid(); actual numeric;
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or t.status<>'active' or not t.single_event_mode or t.race_rules->>'exerciseScoringVersion' is distinct from '2'
    or not exists(select 1 from public.athlth_tournament_entries e where e.tournament_id=t.id and e.user_id=actor
       and e.response='accepted' and e.removed_at is null and e.is_ready and e.agreed_rule_version=t.rule_version)
 then raise exception 'Not an eligible participant'; end if;
 select * into s from private.athlth_shared_event_slots where tournament_id=t.id and candidate_id=p_candidate;
 if not found or s.opens_at is null or clock_timestamp()<s.opens_at or clock_timestamp()>=s.deadline_at or s.closed_at is not null
    or nullif(t.race_rules->>'competitionEndsAt','')::timestamptz<=clock_timestamp()
 then raise exception 'Exercise is not open'; end if;
 select * into d from private.athlth_single_event_exercise_definitions(t.id) where candidate_id=p_candidate;
 if not found or d.metric not in ('distance','duration','repetitions','time') then raise exception 'Invalid exercise'; end if;
 if t.proof_mode='verified' and p_source_workout is null then raise exception 'A verified workout is required'; end if;
 if p_source_workout is not null then
   -- Whole-activity records can establish distance/time only, not a specific strength set.
   if d.activity not in ('running','walking') or d.metric not in ('distance','duration') or d.target_value is null
      then raise exception 'Automatic source matching is not available for this exercise'; end if;
   select w.* into a from public.social_challenge_attempts w join public.social_challenges c on c.id=w.challenge_id
   where w.user_id=actor and w.source_workout_id=p_source_workout and w.verification='athlth' and w.is_eligible
     and c.sport=d.activity and w.started_at>=s.opens_at and w.ended_at<=least(s.deadline_at,clock_timestamp())
     and w.ended_at>w.started_at order by w.submitted_at desc limit 1;
   if not found then raise exception 'Original workout not eligible'; end if;
   if d.metric='distance' and abs(a.distance_meters-d.target_value)<=d.target_value*0.02 then actual:=a.duration_seconds;
   elsif d.metric='duration' and abs(a.duration_seconds-d.target_value)<=5 then actual:=a.distance_meters;
   else raise exception 'Workout does not match the exercise target'; end if;
 else actual:=p_score; end if;
 if actual is null or actual not between 0 and 100000000 or (d.metric='distance' and actual<=0)
    or (d.metric='repetitions' and trunc(actual)<>actual)
    or length(btrim(coalesce(p_evidence,''))) not between 3 and 500 then raise exception 'Invalid result'; end if;
 insert into private.athlth_shared_event_scores(tournament_id,candidate_id,user_id,score,evidence_note,source_workout_id,state,submitted_at)
 values(t.id,p_candidate,actor,actual,btrim(p_evidence),p_source_workout,'submitted',clock_timestamp())
 on conflict(tournament_id,candidate_id,user_id) do update set score=excluded.score,evidence_note=excluded.evidence_note,
  source_workout_id=excluded.source_workout_id,state='submitted',submitted_at=excluded.submitted_at
 where private.athlth_shared_event_scores.state='rejected';
 if not found then raise exception 'Already submitted or decided'; end if;
end;$fn$;
revoke all on function public.athlth_shared_event_submit(uuid,uuid,numeric,text,uuid) from public,anon,authenticated;
grant execute on function public.athlth_shared_event_submit(uuid,uuid,numeric,text,uuid) to authenticated;

create or replace function public.athlth_shared_event_review(p_tournament uuid,p_candidate uuid,p_athlete uuid,p_approve boolean)
returns void language plpgsql security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or t.status<>'active' or t.race_rules->>'exerciseScoringVersion' is distinct from '2'
 then raise exception 'Competition is not active'; end if;
 if t.race_rules->>'duelMode'='true' then
   if actor=p_athlete or not exists(select 1 from public.athlth_tournament_entries e
      where e.tournament_id=t.id and e.user_id=actor and e.response='accepted' and e.removed_at is null)
   or not exists(select 1 from private.athlth_shared_event_scores own where own.tournament_id=t.id
      and own.candidate_id=p_candidate and own.user_id=actor and own.state in ('submitted','approved','missed'))
   then raise exception 'Submit your own result before reviewing your opponent'; end if;
 elsif actor<>t.owner_id then raise exception 'Only the organizer can review'; end if;
 update private.athlth_shared_event_scores r set state=case when p_approve then 'approved' else 'rejected' end
 where r.tournament_id=t.id and r.candidate_id=p_candidate and r.user_id=p_athlete and r.state='submitted';
 if not found then raise exception 'No pending result'; end if;
 perform private.athlth_shared_event_tick(t.id);
end;$fn$;
revoke all on function public.athlth_shared_event_review(uuid,uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.athlth_shared_event_review(uuid,uuid,uuid,boolean) to authenticated;

-- Cap both scheduled and subsequently unlocked league/cup exercise windows.
create or replace function private.athlth_competition_cap_slot_deadline()
returns trigger language plpgsql set search_path='' as $fn$
declare cap timestamptz;
begin
 select nullif(t.race_rules->>'competitionEndsAt','')::timestamptz into cap from public.athlth_tournaments t where t.id=new.tournament_id;
 if cap is not null then new.deadline_at:=least(new.deadline_at,cap); end if;
 return new;
end;$fn$;
drop trigger if exists athlth_competition_cap_slot_deadline on public.athlth_tournament_match_exercises;
create trigger athlth_competition_cap_slot_deadline before insert or update of deadline_at on public.athlth_tournament_match_exercises
 for each row execute function private.athlth_competition_cap_slot_deadline();

create or replace function private.athlth_competition_progress_tick()
returns integer language plpgsql security definer set search_path='' as $fn$
declare t record; n integer:=0;
begin
 for t in select x.id from public.athlth_tournaments x where x.status='active' and x.single_event_mode and x.race_rules->>'exerciseScoringVersion'='2' order by x.created_at limit 250 loop
  begin perform private.athlth_shared_event_tick(t.id); n:=n+1;
  exception when others then raise warning 'Competition progression %: %',t.id,sqlerrm; end;
 end loop;
 -- Incomplete invitations cannot start after the agreed cutoff.
 update public.athlth_tournaments x set status='cancelled',completed_at=clock_timestamp()
 where x.status='inviting' and nullif(x.race_rules->>'competitionEndsAt','')::timestamptz<=clock_timestamp();
 -- Incomplete brackets are not awarded a fictitious winner. Pending submitted
 -- results remain reviewable after the submission cutoff.
 update public.athlth_tournaments x set status='cancelled',completed_at=clock_timestamp()
 where x.status='active' and nullif(x.race_rules->>'competitionEndsAt','')::timestamptz<=clock_timestamp()
 and not (x.single_event_mode and x.race_rules->>'exerciseScoringVersion'='2')
 and not exists(select 1 from public.athlth_tournament_matches m where m.tournament_id=x.id and m.status='proposed')
 and not exists(select 1 from public.athlth_tournament_match_exercises s join public.athlth_tournament_exercise_completions c on c.match_exercise_id=s.id where s.tournament_id=x.id and c.review_status='submitted')
 and not exists(select 1 from public.athlth_tournament_single_event_results r where r.tournament_id=x.id and r.review_status='submitted');
 return n;
end;$fn$;
revoke all on function private.athlth_competition_progress_tick() from public,anon,authenticated;
select cron.schedule('athlth-competition-progress-tick','* * * * *','select private.athlth_competition_progress_tick()');

CREATE OR REPLACE FUNCTION public.athlth_tournament_create_competition(p_title text, p_format text, p_club uuid, p_season uuid, p_group_size integer, p_qualifiers integer, p_invitees uuid[], p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer, p_proposals_close timestamp with time zone, p_votes_close timestamp with time zone, p_approve_player_changes boolean, p_allowed_activities text[], p_rules_authority text, p_cadence_days integer, p_completion_hours integer, p_rotation_mode text, p_rest_weekdays integer[], p_proof_mode text, p_public_results boolean, p_allow_extensions boolean, p_win_points integer, p_draw_points integer, p_setup jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v uuid; v_exercise record; v_count integer:=0;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if nullif(p_setup->'raceRules'->>'competitionEndsAt','') is not null and (
    (p_setup->'raceRules'->>'competitionEndsAt')::timestamptz<=greatest(clock_timestamp(),coalesce((p_setup->>'startsAt')::timestamptz,clock_timestamp()))
    or (p_setup->'raceRules'->>'competitionEndsAt')::timestamptz>clock_timestamp()+interval '366 days')
 then raise exception 'Competition end must be after start and within one year'; end if;
 if p_setup->'raceRules'->>'duelMode'='true' and
    (not coalesce((p_setup->>'singleEventMode')::boolean,false)
     or p_format<>'league' or cardinality(coalesce(p_invitees,array[]::uuid[]))<>1
     or p_invitees[1]=auth.uid() or p_invitees[1] is null
     or p_club is not null or p_season is not null
     or coalesce(p_setup->'raceRules'->>'exerciseScoringVersion','') not in ('1','2')
     or coalesce(p_setup->>'unansweredPolicy','cancel')<>'cancel'
     or coalesce(p_setup->>'invitationPermission','admin')<>'admin'
     or coalesce(p_setup->>'joinApproval','admin')<>'admin'
     or p_public_results) then
   raise exception 'Duel requires exactly two private participants and exercise scoring';
 end if;
 if p_setup->'raceRules'->>'exerciseScoringVersion' in ('1','2') and
    (not coalesce((p_setup->>'singleEventMode')::boolean,false)
     or p_setup->'raceRules'->>'discipline' is distinct from 'workout'
     or coalesce(p_setup->'raceRules'->>'recordingDevice','any')<>'any') then
   raise exception 'Exercise scoring requires a workout-based single event';
 end if;
 if jsonb_typeof(p_setup) is distinct from 'object'
 or (p_setup ? 'raceRules' and (
     jsonb_typeof(p_setup->'raceRules')<>'object'
     or coalesce(p_setup->'raceRules'->>'discipline','workout')
        not in ('sprint','workout','distance','duration','laps')
     or coalesce(p_setup->'raceRules'->>'sprintMode','mass_start')
        not in ('mass_start','relay','staggered')
     or coalesce(p_setup->'raceRules'->>'recordingDevice','any')
        not in ('any','apple_watch','iphone')
     or coalesce(p_setup->'raceRules'->>'lapVerification','gps')
        not in ('gps','supervised')
     or coalesce((p_setup->'raceRules'->>'targetDistanceMeters')::integer,100)
        not between 100 and 100000
     or coalesce((p_setup->'raceRules'->>'targetDurationSeconds')::integer,60)
        not between 10 and 86400
     or coalesce((p_setup->'raceRules'->>'lapCount')::integer,3)
        not between 1 and 500
     or coalesce((p_setup->'raceRules'->>'countdownSeconds')::integer,10)
        not between 5 and 30
     or length(coalesce(p_setup->'raceRules'->>'equipmentRules',''))>350
     or length(coalesce(p_setup->'raceRules'->>'lapCourseName',''))>120
     or (p_setup->'raceRules'->>'discipline'='laps' and
         length(btrim(coalesce(p_setup->'raceRules'->>'lapCourseName','')))=0)
     or (p_setup->'raceRules'->>'discipline'='sprint'
         and not ('running'=any(p_allowed_activities)))
 )) or (coalesce((p_setup->>'singleEventMode')::boolean,false)
     and (p_format<>'league' or coalesce(array_length(p_invitees,1),0)<(case when p_setup->'raceRules'->>'duelMode'='true' then 1 else 2 end)))
 or (p_setup ? 'raceRules' and (
    coalesce(p_setup->'raceRules'->>'recordingDevice','any')<>'any'
    or (p_setup->'raceRules'->>'discipline'='sprint' and
        (coalesce(p_setup->'raceRules'->>'sprintMode','mass_start')<>'mass_start'
         or coalesce(p_setup->'raceRules'->>'sprintTarget','distance')='route'))
    or (p_setup->'raceRules'->>'discipline'='laps' and
        coalesce(p_setup->'raceRules'->>'lapVerification','supervised')='gps')
 ))
 or coalesce(p_setup->>'unlock','interval') not in ('interval','everyone_finished')
 or coalesce(p_setup->>'unit','day') not in ('minute','hour','day','month')
 or coalesce((p_setup->>'every')::int,7) not between 1 and 10080
 or coalesce((p_setup->>'invitationDays')::integer,3) not between 1 and 30
 or coalesce(p_setup->>'unansweredPolicy','cancel') not in ('cancel','continue','replace')
 or coalesce(p_setup->>'startMode','manual') not in ('manual','when_ready','scheduled')
 or (coalesce(p_setup->>'startMode','manual')='scheduled'
     and nullif(p_setup->>'startsAt','') is null)
 or coalesce(p_setup->>'environment','any') not in ('any','outdoor','gym')
 or (coalesce(p_setup->>'environment','any')='outdoor'
    and not (p_allowed_activities && array['running','walking','hiking']))
 or (coalesce(p_setup->>'environment','any')='gym'
    and not ('strength'=any(p_allowed_activities)))
 or length(coalesce(p_setup->>'meetingPlace',''))>240
 or ((p_setup ? 'meetingLat') <> (p_setup ? 'meetingLon'))
 or (p_setup ? 'meetingLat' and
   ((p_setup->>'meetingLat')::numeric not between -90 and 90 or
    (p_setup->>'meetingLon')::numeric not between -180 and 180))
 or coalesce(p_setup->>'invitationPermission','admin') not in ('admin','participants')
 or coalesce(p_setup->>'joinApproval','admin') not in ('open','participants','admin')
 or (p_setup->>'startsAt')::timestamptz > clock_timestamp()+interval '366 days'
 or (p_setup->>'startsAt')::timestamptz < clock_timestamp()-interval '1 minute'
 or greatest(length(coalesce(p_setup->>'allowed','')),length(coalesce(p_setup->>'prohibited','')),
 length(coalesce(p_setup->>'firstPrize','')),length(coalesce(p_setup->>'secondPrize','')),
 length(coalesce(p_setup->>'thirdPrize','')),length(coalesce(p_setup->>'loserConsequence','')))>500
 then raise exception 'Invalid competition settings'; end if;
 -- League: two people allowed; Cup: minimum four including organizer.
 if (p_format='cup' and coalesce(array_length(p_invitees,1),0)<3)
     or (p_format in ('league','groups') and coalesce(array_length(p_invitees,1),0)<1) then
   raise exception 'Liga needs two; cup needs four accepted participants';
 end if;
 v:=public.athlth_tournament_create_accepted_rules(
 p_title,p_format,p_club,p_season,p_group_size,p_qualifiers,p_invitees,
 p_warmup_titles,p_exercise_mode,p_exercise_count,p_proposals_close,
 p_votes_close,p_approve_player_changes,p_allowed_activities,p_rules_authority,
 p_cadence_days,p_completion_hours,p_rotation_mode,p_rest_weekdays,
 p_proof_mode,p_public_results,p_allow_extensions,p_win_points,p_draw_points);
 update public.athlth_tournaments
 set single_event_mode=coalesce((p_setup->>'singleEventMode')::boolean,false),
 planned_starts_at=(p_setup->>'startsAt')::timestamptz,
 invitation_days=coalesce((p_setup->>'invitationDays')::integer,3),
 unanswered_policy=coalesce(p_setup->>'unansweredPolicy','cancel'),
 allow_feed_post=coalesce((p_setup->>'allowFeedPost')::boolean,true),
 start_mode=coalesce(p_setup->>'startMode','manual'),
 required_environment=coalesce(p_setup->>'environment','any'),
 meeting_place=nullif(btrim(p_setup->>'meetingPlace'),''),
 meeting_lat=(p_setup->>'meetingLat')::double precision,
 meeting_lon=(p_setup->>'meetingLon')::double precision,
 race_rules=coalesce(p_setup->'raceRules',race_rules),
 release_mode=coalesce(p_setup->>'unlock','interval'),
 release_every=coalesce((p_setup->>'every')::int,7),
 release_unit=coalesce(p_setup->>'unit','day'),
 invitation_permission=coalesce(p_setup->>'invitationPermission','admin'),
 join_approval=coalesce(p_setup->>'joinApproval','admin'),
 allowed_actions=coalesce(p_setup->>'allowed',''),
 prohibited_actions=coalesce(p_setup->>'prohibited',''),
 prize_first=coalesce(p_setup->>'firstPrize',''),
 prize_second=coalesce(p_setup->>'secondPrize',''),
 prize_third=coalesce(p_setup->>'thirdPrize',''),
 loser_consequence=coalesce(p_setup->>'loserConsequence','')
 where id=v and owner_id=auth.uid() and status='inviting';
 if not found then raise exception 'Competition was not configured'; end if;
 update public.athlth_tournament_entries e
 set invited_at=coalesce(e.invited_at,clock_timestamp()),
     expires_at=coalesce(e.invited_at,clock_timestamp())+
         make_interval(days=>coalesce((p_setup->>'invitationDays')::integer,3))
 where e.tournament_id=v and e.response='invited';
 if p_setup ? 'coachExerciseIDs' then
   if p_exercise_mode <> 'owner'
      or jsonb_typeof(p_setup->'coachExerciseIDs')<>'array'
      or jsonb_array_length(p_setup->'coachExerciseIDs') not between 1 and 12 then
       raise exception 'Invalid Coach exercise proposal';
   end if;
   for v_exercise in
       select value::uuid as id, ordinality::integer as position
       from jsonb_array_elements_text(p_setup->'coachExerciseIDs')
            with ordinality
   loop
       if not exists(
         select 1 from public.athlth_tournament_activity_templates item
         where item.id=v_exercise.id and item.is_active
           and item.activity_type=any(p_allowed_activities)
       ) then raise exception 'Coach suggested an unavailable exercise'; end if;
       insert into public.athlth_tournament_exercise_candidates(
           tournament_id,activity_template_id,suggested_by,selected_position
       ) values(v,v_exercise.id,auth.uid(),v_exercise.position);
       v_count:=v_count+1;
   end loop;
   if v_count<>p_exercise_count then
     raise exception 'Coach exercise count mismatch';
   end if;
   update public.athlth_tournaments
      set exercise_selection_finalized_at=clock_timestamp()
      where id=v and owner_id=auth.uid();
 end if;
 return v;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.athlth_competition_start_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if old.status is distinct from new.status and new.status='active' and
    nullif(new.race_rules->>'competitionEndsAt','')::timestamptz <= clock_timestamp()
 then raise exception 'Competition end has already passed'; end if;
 if old.status is distinct from new.status and new.status='active' and
    new.planned_starts_at is not null and
    clock_timestamp()<new.planned_starts_at then
    raise exception 'Competition cannot start before its planned date';
 end if;
 if old.status is distinct from new.status and new.status='active' and
    new.competition_settings_applied and
    (select count(*) from public.athlth_tournament_entries e
     where e.tournament_id=new.id and e.response='accepted'
       and e.removed_at is null)<(private.athlth_competition_minimum_athletes(new.format,new.single_event_mode,new.race_rules)) then
    raise exception 'Liga requires two; cup requires four accepted athletes';
 end if;
 if old.status is distinct from new.status and new.status='active'
   and new.race_rules->>'duelMode'='true'
   and (select count(*) from public.athlth_tournament_entries e where e.tournament_id=new.id and e.response='accepted' and e.removed_at is null)<>2
 then raise exception 'Duel requires exactly two accepted athletes'; end if;
 if old.rules_frozen_at is not null and
   (old.planned_starts_at is distinct from new.planned_starts_at or
    old.release_mode is distinct from new.release_mode or
    old.release_every is distinct from new.release_every or
    old.release_unit is distinct from new.release_unit or
    old.invitation_permission is distinct from new.invitation_permission or
    old.join_approval is distinct from new.join_approval or
    old.allowed_actions is distinct from new.allowed_actions or
    old.prohibited_actions is distinct from new.prohibited_actions or
    old.prize_first is distinct from new.prize_first or
    old.prize_second is distinct from new.prize_second or
    old.prize_third is distinct from new.prize_third or
    old.loser_consequence is distinct from new.loser_consequence or
    old.start_mode is distinct from new.start_mode or
    old.required_environment is distinct from new.required_environment or
    old.meeting_place is distinct from new.meeting_place or
    old.meeting_lat is distinct from new.meeting_lat or
    old.meeting_lon is distinct from new.meeting_lon or
    old.race_rules is distinct from new.race_rules or
    old.invitation_days is distinct from new.invitation_days or
    old.unanswered_policy is distinct from new.unanswered_policy or
    old.allow_feed_post is distinct from new.allow_feed_post)
 then raise exception 'Competition rules are locked'; end if;
 return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.athlth_competition_start_internal(p_tournament uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_actor uuid := auth.uid();
    v_t public.athlth_tournaments%rowtype;
    v_members uuid[];
    v_count integer;
    v_pending integer;
    v_groups integer;
    v_group integer;
    v_group_members uuid[];
    v_warmups integer;
    v_index integer;
begin
    select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
    if not found or not v_t.competition_settings_applied then
        raise exception 'Not a configured competition';
    end if;
    if v_actor is not null then
       if v_actor<>v_t.owner_id or v_t.start_mode<>'manual' then
          raise exception 'Only the organizer can start manual competitions';
       end if;
    elsif v_t.start_mode='manual' then
       raise exception 'Manual competitions need an organizer';
    end if;
    if v_t.start_mode='scheduled' and
       (v_t.planned_starts_at is null or clock_timestamp()<v_t.planned_starts_at) then
       raise exception 'Scheduled start time is not reached';
    end if;
    if v_t.unanswered_policy='replace' and v_t.replacement_until is not null
    then raise exception 'Finish replacement before starting'; end if;
    if nullif(v_t.race_rules->>'competitionEndsAt','')::timestamptz <= clock_timestamp()+make_interval(secs=>coalesce((v_t.race_rules->>'countdownSeconds')::integer,10)) then
        raise exception 'Competition end is before the start signal';
    end if;
    if v_t.status<>'inviting' then
        raise exception 'Tournament is not awaiting invitations';
    end if;
    if v_t.rules_confirmed_at is null then
       raise exception 'Group rules must be approved before starting';
    end if;
    if v_t.exercise_selection_finalized_at is null or
       (select count(*) from public.athlth_tournament_exercise_candidates
        where tournament_id=p_tournament and selected_position is not null)
         <> v_t.exercise_count then
        raise exception 'Finalize the exercise list before starting';
    end if;
    if exists(
        select 1 from public.athlth_tournament_entries e
        where e.tournament_id=p_tournament and e.response='accepted'
          and (e.is_ready is not true or e.removed_at is not null
              or e.agreed_rule_version is distinct from v_t.rule_version)
    ) then
        raise exception 'All accepted participants must press Ready';
    end if;
    select count(*) into v_pending from public.athlth_tournament_entries
    where tournament_id=p_tournament and response='invited';
    if v_pending<>0 then
        raise exception 'Wait for every invited athlete to respond';
    end if;
    -- Fair, tamper-resistant draw. The organizer is NOT automatically
    -- assigned the first seed or any potential bye.
    select array_agg(user_id order by draw_key,user_id) into v_members
    from (
        select user_id, random() as draw_key
        from public.athlth_tournament_entries
        where tournament_id=p_tournament and response='accepted'
    ) shuffled;
    v_count := coalesce(array_length(v_members,1),0);
    if (v_t.format='cup' and v_count<4)
       or (v_t.format in ('league','groups') and v_count<2)
    then raise exception 'League requires two; cup requires four accepted athletes'; end if;
    if v_t.race_rules->>'duelMode'='true' and v_count<>2 then
        raise exception 'Duel requires exactly two ready athletes';
    end if;
    if v_t.single_event_mode and v_t.race_rules->>'duelMode' is distinct from 'true' and v_count<3 then
        raise exception 'A single event requires at least three ready athletes';
    end if;
    for v_index in 1..v_count loop
        update public.athlth_tournament_entries
           set draw_position=v_index
         where tournament_id=p_tournament
           and user_id=v_members[v_index];
    end loop;

    if v_t.format='groups' and v_count<=v_t.group_size then
        raise exception 'Choose more athletes than one group, or use league';
    end if;
    select count(*) into v_warmups from public.athlth_tournament_practice
    where tournament_id=p_tournament;
    if v_warmups>0 then
        perform private.athlth_schedule_round_robin(
            p_tournament,v_members,'warmup',null,v_warmups
        );
    end if;
    if v_t.single_event_mode then
        if v_t.race_rules->>'exerciseScoringVersion' in ('1','2') and (
          v_t.race_rules->>'discipline' is distinct from 'workout'
          or coalesce(v_t.race_rules->>'recordingDevice','any')<>'any'
          or v_t.exercise_count<1
          or (select count(*) from private.athlth_single_event_exercise_definitions(p_tournament))<>v_t.exercise_count
          or exists(select 1 from private.athlth_single_event_exercise_definitions(p_tournament) d
             where d.metric not in ('distance','duration','repetitions','time')
                or not (d.activity=any(v_t.allowed_activities)))
        ) then raise exception 'Finalize a valid exercise scoring list before starting'; end if;
        update public.athlth_tournaments
        set status='active',started_at=clock_timestamp(),
            rules_frozen_at=clock_timestamp(),
            race_signal_at=clock_timestamp()+make_interval(
              secs=>coalesce((v_t.race_rules->>'countdownSeconds')::integer,10))
        where id=p_tournament;
        insert into public.athlth_tournament_audit(
            tournament_id,actor_id,event,info)
        values(p_tournament,coalesce(v_actor,v_t.owner_id),'started',
          jsonb_build_object('accepted',v_count,'single_event',true));
        return;
    elsif v_t.format='league' then
        perform private.athlth_schedule_round_robin(
            p_tournament,v_members,'league',null,null
        );
    elsif v_t.format='groups' then
        v_groups := ceil(v_count::numeric / v_t.group_size)::integer;
        if v_count<2*v_groups or
           v_t.qualifiers_per_group>floor(v_count::numeric/v_groups) then
            raise exception 'Group size or qualifiers would create an unfair one-person group';
        end if;
        for v_index in 1..v_count loop
            update public.athlth_tournament_entries
               set group_index=(v_index-1) % v_groups
             where tournament_id=p_tournament
               and user_id=v_members[v_index];
        end loop;
        for v_group in 0..(v_groups-1) loop
            select array_agg(user_id order by draw_position) into v_group_members
            from public.athlth_tournament_entries
            where tournament_id=p_tournament and response='accepted'
              and group_index=v_group;
            perform private.athlth_schedule_round_robin(
                p_tournament,v_group_members,'group',v_group,null
            );
        end loop;
    else
        perform private.athlth_schedule_knockout(
            p_tournament,v_members,'cup',1
        );
    end if;
    update public.athlth_tournaments
    set status='active',started_at=now(),rules_frozen_at=now() where id=p_tournament;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(p_tournament,coalesce(v_actor,v_t.owner_id),'started',
        jsonb_build_object('accepted',v_count,'warmups',v_warmups));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.athlth_tournament_single_event_submit(p_tournament uuid, p_score numeric, p_laps integer, p_evidence text, p_source_workout uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.athlth_tournaments%rowtype;
 actor uuid:=auth.uid(); candidate record; official numeric;
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or not t.single_event_mode or t.status<>'active'
   or t.race_signal_at is null or clock_timestamp()<t.race_signal_at then
   raise exception 'The competition has not started'; end if;
 if not exists(select 1 from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.user_id=actor
      and e.response='accepted' and e.is_ready and e.removed_at is null) then
   raise exception 'You are not a ready participant'; end if;
 if t.race_rules->>'exerciseScoringVersion' in ('1','2') then
   raise exception 'Submit individual exercise scores with the updated ATHLTH app';
 end if;
 if nullif(t.race_rules->>'competitionEndsAt','')::timestamptz <= clock_timestamp() then
   raise exception 'Competition submission deadline has passed'; end if;
 if p_score is null or p_score not between 0 and 100000000
   or length(btrim(coalesce(p_evidence,''))) not between 3 and 500
   or (p_laps is not null and p_laps not between 0 and 500) then
   raise exception 'Provide a valid result and evidence'; end if;
 if (t.race_rules->>'discipline')='laps' and
    p_laps is distinct from (t.race_rules->>'lapCount')::integer then
    raise exception 'A completed entry must include the required laps'; end if;
 if p_source_workout is not null then
    select a.distance_meters,a.duration_seconds,a.volume_kilograms,
           a.route_match_percent
      into candidate
    from public.social_challenge_attempts a
    where a.user_id=actor and a.source_workout_id=p_source_workout
    and a.verification='athlth' and a.is_eligible
    and a.started_at>=t.race_signal_at and a.ended_at<=clock_timestamp()
    order by a.submitted_at desc limit 1;
    if not found then raise exception 'Workout is not verified for this start'; end if;
    if (t.race_rules->>'discipline')='sprint' then
      if (t.race_rules->>'sprintMode')<>'mass_start' then
        raise exception 'Relay and staggered sprint require separate start slots';
      end if;
      if t.race_rules->>'sprintTarget'='route' then
        raise exception 'Route identity verification is not available yet';
      elsif t.race_rules->>'sprintTarget'='duration' then
        if candidate.duration_seconds is null or
           candidate.duration_seconds>(t.race_rules->>'targetDurationSeconds')::numeric+5
           or candidate.distance_meters is null then
          raise exception 'Timed sprint did not meet the prescribed limit';
        end if;
        official:=candidate.distance_meters;
      else
        if candidate.distance_meters<
              (t.race_rules->>'targetDistanceMeters')::numeric
           or candidate.duration_seconds is null or candidate.duration_seconds<=0
        then raise exception 'Sprint distance was not completed'; end if;
        official:=candidate.duration_seconds;
      end if;
      if abs(official-p_score)>0.01 then
        raise exception 'Sprint score must match verified workout data';
      end if;
    end if;
 end if;
 -- Do not accept an unverified time-based sprint result. Health recording
 -- origin is not yet available in this table, so Watch-only requires a
 -- separately verified capture pipeline before such results can be approved.
 if (t.race_rules->>'discipline')='sprint' and p_source_workout is null then
   raise exception 'A verified ATHLTH workout is required for sprint'; end if;
 if (t.race_rules->>'recordingDevice')='apple_watch' then
   raise exception 'Apple Watch source attestation is not available yet'; end if;
 insert into public.athlth_tournament_single_event_results(
   tournament_id,user_id,reported_score,reported_laps,evidence_note,
   source_workout_id,review_status,submitted_at,reviewed_at,reviewed_by
 ) values(t.id,actor,p_score,p_laps,btrim(p_evidence),p_source_workout,
      'submitted',clock_timestamp(),null,null)
 on conflict(tournament_id,user_id)
 do update set reported_score=excluded.reported_score,
    reported_laps=excluded.reported_laps,evidence_note=excluded.evidence_note,
    source_workout_id=excluded.source_workout_id,review_status='submitted',
    submitted_at=excluded.submitted_at,reviewed_at=null,reviewed_by=null
 where public.athlth_tournament_single_event_results.review_status<>'approved';
 if not found then raise exception 'Approved results cannot be changed'; end if;
end;$function$
;

CREATE OR REPLACE FUNCTION public.athlth_tournament_single_event_submit_exercises(p_tournament uuid, p_scores jsonb, p_evidence text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
 d record; value_json jsonb; result_value numeric; actual_count integer;
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or not t.single_event_mode or t.status<>'active'
   or t.race_signal_at is null or clock_timestamp()<t.race_signal_at
   or t.race_rules->>'exerciseScoringVersion' is distinct from '1'
   or nullif(t.race_rules->>'competitionEndsAt','')::timestamptz <= clock_timestamp()
   or t.race_rules->>'discipline' is distinct from 'workout'
   or coalesce(t.race_rules->>'recordingDevice','any')<>'any'
   then raise exception 'Exercise scoring is not available for this event'; end if;
 if not exists(select 1 from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.user_id=actor and e.response='accepted'
      and e.is_ready and e.removed_at is null and e.agreed_rule_version=t.rule_version)
   then raise exception 'You are not a ready participant'; end if;
 if jsonb_typeof(p_scores) is distinct from 'object'
   or octet_length(p_scores::text)>50000
   or length(btrim(coalesce(p_evidence,''))) not between 3 and 500
   then raise exception 'Provide scores and evidence for every exercise'; end if;
 select count(*) into actual_count from private.athlth_single_event_exercise_definitions(t.id);
 if actual_count<1 or actual_count<>t.exercise_count
   or (select count(*) from jsonb_object_keys(p_scores))<>actual_count
   then raise exception 'Every finalized exercise requires a score'; end if;
 for d in select * from private.athlth_single_event_exercise_definitions(t.id) loop
   if d.metric not in ('distance','duration','repetitions','time')
     or not (d.activity=any(t.allowed_activities)) then raise exception 'Invalid exercise definition'; end if;
   value_json:=p_scores->(d.candidate_id::text);
   if jsonb_typeof(value_json) is distinct from 'number' then raise exception 'Invalid exercise score'; end if;
   result_value:=(value_json #>> '{}')::numeric;
   if result_value not between 0 and 100000000
     or (d.metric='distance' and result_value<=0)
     or (d.metric='repetitions' and trunc(result_value)<>result_value)
     then raise exception 'Invalid exercise score'; end if;
 end loop;
 insert into public.athlth_tournament_single_event_results(
    tournament_id,user_id,reported_score,evidence_note,exercise_scores,review_status,submitted_at)
 values(t.id,actor,0,btrim(p_evidence),p_scores,'submitted',clock_timestamp())
 on conflict(tournament_id,user_id) do update
 set reported_score=0,evidence_note=excluded.evidence_note,exercise_scores=excluded.exercise_scores,
   reported_laps=null,source_workout_id=null,review_status='submitted',
   submitted_at=excluded.submitted_at,reviewed_at=null,reviewed_by=null
 where public.athlth_tournament_single_event_results.review_status<>'approved';
 if not found then raise exception 'Approved results cannot be changed'; end if;
end;$function$
;

CREATE OR REPLACE FUNCTION public.athlth_tournament_single_event_review(p_tournament uuid, p_athlete uuid, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.athlth_tournaments%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or not t.single_event_mode or t.status<>'active'
    then raise exception 'Competition not active'; end if;
 if t.race_rules->>'exerciseScoringVersion'='2' then raise exception 'Review each exercise separately'; end if;
 if t.race_rules->>'duelMode'='true' then
    if p_athlete=auth.uid() or not exists(select 1 from public.athlth_tournament_entries e
       where e.tournament_id=t.id and e.user_id=auth.uid() and e.response='accepted' and e.removed_at is null)
       or not exists(select 1 from public.athlth_tournament_single_event_results r
       where r.tournament_id=t.id and r.user_id=auth.uid() and r.review_status in ('submitted','approved'))
    then raise exception 'Submit your own result before reviewing your opponent'; end if;
 else
    if t.owner_id<>auth.uid() then raise exception 'Only the event organizer may review results'; end if;
 end if;
 update public.athlth_tournament_single_event_results r
 set review_status=case when p_approve then 'approved' else 'rejected' end,
     reviewed_at=clock_timestamp(),reviewed_by=auth.uid()
 where r.tournament_id=t.id and r.user_id=p_athlete
   and r.review_status='submitted'
   and (t.race_rules->>'exerciseScoringVersion' is distinct from '1' or r.exercise_scores is not null);
 if not found then raise exception 'No pending result'; end if;
 if not exists(
     select 1 from public.athlth_tournament_entries e
     where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
       and not exists(select 1 from public.athlth_tournament_single_event_results r
         where r.tournament_id=t.id and r.user_id=e.user_id
           and r.review_status='approved')
 ) then
   if t.race_rules->>'exerciseScoringVersion'='1' then
      with ranked as (
        select r.user_id,d.candidate_id,
          count(*) over(partition by d.candidate_id) as athlete_count,
          rank() over(partition by d.candidate_id order by
            case when d.metric='distance' then (r.exercise_scores->>(d.candidate_id::text))::numeric end asc nulls last,
            case when d.metric<>'distance' then (r.exercise_scores->>(d.candidate_id::text))::numeric end desc nulls last
          ) as placement
        from public.athlth_tournament_single_event_results r
        join public.athlth_tournament_entries e on e.tournament_id=r.tournament_id and e.user_id=r.user_id
        cross join private.athlth_single_event_exercise_definitions(t.id) d
        where r.tournament_id=t.id and r.review_status='approved'
          and e.response='accepted' and e.removed_at is null
      ), totals as (
        select x.user_id,sum(x.athlete_count-x.placement+1) as points from ranked x group by x.user_id
      )
      update public.athlth_tournament_single_event_results r set reported_score=totals.points
      from totals where r.tournament_id=t.id and r.user_id=totals.user_id;
   end if;
   update public.athlth_tournaments set status='completed',
       completed_at=clock_timestamp() where id=t.id;
   insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
   values(t.id,auth.uid(),'single_event_completed');
 end if;
end;$function$
;

CREATE OR REPLACE FUNCTION public.athlth_tournament_propose_result(p_match uuid, p_home_score numeric, p_away_score numeric, p_evidence text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user uuid := auth.uid();
    v_match public.athlth_tournament_matches%rowtype;
    v_t_status text;
begin
    if v_user is null then raise exception 'Sign in required'; end if;
    select * into v_match from public.athlth_tournament_matches
    where id=p_match for update;
    if not found or v_user not in (v_match.home_id,v_match.away_id) or
       v_match.away_id is null or
       v_match.status not in ('scheduled','disputed') then
        raise exception 'Not eligible to propose a result';
    end if;
    if v_match.scheduled_at is not null
       and clock_timestamp()<v_match.scheduled_at then
        raise exception 'This match is scheduled for a future round';
    end if;
    select status into v_t_status from public.athlth_tournaments
    where id=v_match.tournament_id for update;
    if v_t_status <> 'active' or not exists(
        select 1 from public.athlth_tournament_entries e
        where e.tournament_id=v_match.tournament_id
        and e.user_id=v_user and e.response='accepted'
    ) then raise exception 'Tournament is not active for this athlete'; end if;
    if exists(select 1 from public.athlth_tournaments t where t.id=v_match.tournament_id
       and nullif(t.race_rules->>'competitionEndsAt','')::timestamptz<=clock_timestamp()) then
       raise exception 'Competition submission deadline has passed'; end if;
    if p_home_score is null or p_away_score is null or
       p_home_score < 0 or p_away_score < 0 or
       p_home_score > 100000000 or p_away_score > 100000000 or
       (v_match.phase in ('cup','playoff') and p_home_score=p_away_score) or
       length(btrim(coalesce(p_evidence,''))) > 400 then
        raise exception 'Invalid match score or evidence';
    end if;
    update public.athlth_tournament_matches
       set home_score=p_home_score,away_score=p_away_score,
           status='proposed',proposed_by=v_user,
           confirmed_by=null,confirmed_at=null,
           evidence_note=btrim(coalesce(p_evidence,''))
     where id=p_match;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(
        v_match.tournament_id,v_user,'result_proposed',
        jsonb_build_object('match',p_match)
    );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.athlth_tournament_complete_exercise(p_match_exercise uuid, p_evidence_note text, p_source_workout uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_user uuid:=auth.uid();
 v_ex public.athlth_tournament_match_exercises%rowtype;
 v_match public.athlth_tournament_matches%rowtype;
 v_state text;
 v_race jsonb;
 v_started timestamptz;
 v_verified_attempt record;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_ex from public.athlth_tournament_match_exercises
 where id=p_match_exercise for update;
 if not found or v_ex.state<>'pending' or now()>v_ex.deadline_at then
   raise exception 'Exercise deadline has passed';
 end if;
 select * into v_match from public.athlth_tournament_matches
 where id=v_ex.match_id;
 select status,race_rules into v_state,v_race
 from public.athlth_tournaments
 where id=v_ex.tournament_id;
 if v_state<>'active' or v_match.status='confirmed' or
    v_user not in (v_match.home_id,v_match.away_id) or
    not private.athlth_tournament_is_accepted(v_ex.tournament_id) then
   raise exception 'This exercise is not open to this athlete';
 end if;
 if exists(select 1 from public.athlth_tournaments t where t.id=v_ex.tournament_id
       and nullif(t.race_rules->>'competitionEndsAt','')::timestamptz<=clock_timestamp()) then
       raise exception 'Competition submission deadline has passed'; end if;
 if v_ex.scheduled_at>now() then
   raise exception 'Exercise has not started';
 end if;
 if coalesce(v_race->>'recordingDevice','any')<>'any' then
    raise exception 'Capture device source has not been verified';
 end if;
 if v_race->>'discipline'='sprint' then
   if p_source_workout is null then
     raise exception 'Sprint requires a verified workout';
   end if;
   if coalesce(v_race->>'sprintMode','mass_start')<>'mass_start'
      or v_race->>'sprintTarget'='route' then
     raise exception 'Sprint start type is not yet supported';
   end if;
   v_started:=v_ex.scheduled_at+
     make_interval(secs=>coalesce((v_race->>'countdownSeconds')::integer,10));
   if clock_timestamp()<v_started then
     raise exception 'Start signal has not been given';
   end if;
   select a.started_at,a.ended_at,a.distance_meters,a.duration_seconds
      into v_verified_attempt
     from public.social_challenge_attempts a
    where a.user_id=v_user and a.source_workout_id=p_source_workout
      and a.verification='athlth' and a.is_eligible
      and a.started_at>=v_started
      and a.ended_at<=v_ex.deadline_at
    order by a.submitted_at desc limit 1;
   if not found then
     raise exception 'Sprint workout started too early or is unverified';
   end if;
   if coalesce(v_race->>'sprintTarget','distance')='duration' then
     if v_verified_attempt.duration_seconds>
        (v_race->>'targetDurationSeconds')::numeric+5 or
        v_verified_attempt.distance_meters is null then
       raise exception 'Timed sprint limit was not met';
     end if;
   elsif v_verified_attempt.distance_meters<
          (v_race->>'targetDistanceMeters')::numeric then
     raise exception 'Sprint distance was not completed';
   end if;
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
$function$
;
