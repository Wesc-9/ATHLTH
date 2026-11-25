-- Enforce a transparent, bounded review window for newly agreed scoring rules.
alter table private.athlth_shared_event_scores add column if not exists auto_approved boolean not null default false;
alter table public.athlth_tournament_exercise_completions add column if not exists auto_approved boolean not null default false;
CREATE OR REPLACE FUNCTION public.athlth_tournament_create_competition(p_title text, p_format text, p_club uuid, p_season uuid, p_group_size integer, p_qualifiers integer, p_invitees uuid[], p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer, p_proposals_close timestamp with time zone, p_votes_close timestamp with time zone, p_approve_player_changes boolean, p_allowed_activities text[], p_rules_authority text, p_cadence_days integer, p_completion_hours integer, p_rotation_mode text, p_rest_weekdays integer[], p_proof_mode text, p_public_results boolean, p_allow_extensions boolean, p_win_points integer, p_draw_points integer, p_setup jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v uuid; v_exercise record; v_count integer:=0; previous public.athlth_tournaments%rowtype; parent_id uuid; previous_number integer; selected_ids jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_setup->'raceRules' ? 'scoringMode' then
   if p_setup->'raceRules'->>'scoringMode' not in ('ranking','winner','target','closest','completion')
      or p_setup->'raceRules'->>'discipline' is distinct from 'workout'
      or p_proof_mode<>'opponent'
      or coalesce((p_setup->'raceRules'->>'pointsPerExercise')::integer,1) not between 1 and 10
      or coalesce((p_setup->'raceRules'->>'reviewHours')::integer,48) not between 12 and 168
      then raise exception 'Invalid scoring method or unsupported verification'; end if;
   if jsonb_typeof(coalesce(p_setup->'raceRules'->'handicapPercentages','{}'::jsonb))<>'object'
      or jsonb_typeof(coalesce(p_setup->'raceRules'->'scoringGoals','{}'::jsonb))<>'object'
      or jsonb_typeof(coalesce(p_setup->'raceRules'->'exerciseWeights','{}'::jsonb))<>'object'
      then raise exception 'Invalid scoring configuration'; end if;
   if exists(select 1 from jsonb_each(coalesce(p_setup->'raceRules'->'handicapPercentages','{}')) h
     where h.key::uuid not in (select auth.uid() union select unnest(p_invitees))
       or jsonb_typeof(h.value)<>'number' or (h.value #>> '{}')::numeric not between 0 and 30
       or (h.value #>> '{}')::numeric<>trunc((h.value #>> '{}')::numeric))
   then raise exception 'Handicap must be 0–30 percent for an invited participant'; end if;
   if exists(select 1 from jsonb_each(coalesce(p_setup->'raceRules'->'scoringGoals','{}')) g
     where jsonb_typeof(g.value)<>'number' or (g.value #>> '{}')::numeric not between 0.000001 and 100000000
        or not exists(select 1 from jsonb_array_elements_text(coalesce(p_setup->'selectedExerciseIDs','[]'::jsonb)) x(id) where lower(x.id)=g.key))
   then raise exception 'Invalid exercise goal'; end if;
   if exists(select 1 from jsonb_each(coalesce(p_setup->'raceRules'->'exerciseWeights','{}')) w
     where jsonb_typeof(w.value)<>'number' or (w.value #>> '{}')::numeric not between 1 and 5
        or (w.value #>> '{}')::numeric<>trunc((w.value #>> '{}')::numeric)
        or not exists(select 1 from jsonb_array_elements_text(coalesce(p_setup->'selectedExerciseIDs','[]'::jsonb)) x(id) where lower(x.id)=w.key))
   then raise exception 'Invalid exercise weight'; end if;
   if p_setup->'raceRules'->>'scoringMode' in ('target','closest') and
      (not (p_setup ? 'selectedExerciseIDs') or exists(
         select 1 from jsonb_array_elements_text(p_setup->'selectedExerciseIDs') x(id)
         where not coalesce(p_setup->'raceRules'->'scoringGoals','{}'::jsonb) ? lower(x.id)))
   then raise exception 'Set a goal for each explicitly selected exercise'; end if;
 end if;
 parent_id:=nullif(p_setup->'raceRules'->>'previousCompetitionID','')::uuid;
 if parent_id is not null then
   select * into previous from public.athlth_tournaments where id=parent_id for update;
   if not found or previous.status<>'completed' then raise exception 'Previous competition must be completed'; end if;
   if previous.race_rules->>'duelMode'='true' then
     if auth.uid()=previous.owner_id or p_setup->'raceRules'->>'duelMode' is distinct from 'true'
       or cardinality(coalesce(p_invitees,array[]::uuid[]))<>1 or p_invitees[1] is distinct from previous.owner_id
       or not exists(select 1 from public.athlth_tournament_entries e where e.tournament_id=previous.id and e.user_id=auth.uid() and e.response='accepted' and e.removed_at is null)
       or p_setup->'raceRules' ? 'seasonNumber'
       or p_exercise_mode<>'owner' or not (p_setup ? 'selectedExerciseIDs')
     then raise exception 'The previous invited athlete chooses the rematch exercises'; end if;
   else
     previous_number:=coalesce((previous.race_rules->>'seasonNumber')::integer,1);
     if previous.single_event_mode or previous.owner_id<>auth.uid() or p_format<>previous.format
       or p_club is distinct from previous.club_id
       or coalesce((p_setup->>'singleEventMode')::boolean,false)
       or (p_setup->'raceRules'->>'seasonNumber')::integer is distinct from previous_number+1
     then raise exception 'Invalid next season'; end if;
   end if;
   if exists(select 1 from public.athlth_tournaments t where (t.race_rules->>'previousCompetitionID')::uuid=parent_id and t.status<>'cancelled')
   then raise exception 'A continuation already exists'; end if;
 elsif p_setup->'raceRules' ? 'seasonNumber' and
   (coalesce((p_setup->>'singleEventMode')::boolean,false) or (p_setup->'raceRules'->>'seasonNumber')::integer is distinct from 1)
 then raise exception 'First season must be season 1'; end if;
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
 if p_setup->'raceRules'->>'exerciseScoringVersion'='2' and p_proof_mode='verified' then
   raise exception 'Automatic source attestation is not supported for every selected exercise';
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
 or coalesce(p_setup->>'unlock','interval') not in ('interval','everyone_finished','all_at_start')
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
 if p_setup ? 'selectedExerciseIDs' and p_setup ? 'coachExerciseIDs' then raise exception 'Choose one exercise list'; end if;
 selected_ids:=coalesce(p_setup->'selectedExerciseIDs',p_setup->'coachExerciseIDs');
 if selected_ids is not null then
   if p_exercise_mode <> 'owner'
      or jsonb_typeof(selected_ids)<>'array'
      or jsonb_array_length(selected_ids) not between 1 and 12 then
       raise exception 'Invalid Coach exercise proposal';
   end if;
   for v_exercise in
       select value::uuid as id, ordinality::integer as position
       from jsonb_array_elements_text(selected_ids)
            with ordinality
   loop
       if exists(
         select 1 from public.athlth_tournament_activity_templates item
         where item.id=v_exercise.id and item.is_active
           and item.activity_type=any(p_allowed_activities)
       ) then
         insert into public.athlth_tournament_exercise_candidates(
           tournament_id,activity_template_id,suggested_by,selected_position
         ) values(v,v_exercise.id,auth.uid(),v_exercise.position);
       elsif p_setup ? 'selectedExerciseIDs' and 'strength'=any(p_allowed_activities)
         and exists(select 1 from public.exercise_catalog e where e.id=v_exercise.id and e.is_published
           and e.category in ('strength','core','strength-endurance','carry','conditioning'))
       then
         insert into public.athlth_tournament_exercise_candidates(
           tournament_id,exercise_id,suggested_by,selected_position
         ) values(v,v_exercise.id,auth.uid(),v_exercise.position);
       else raise exception 'Selected exercise is not available in the chosen branches'; end if;
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

CREATE OR REPLACE FUNCTION private.athlth_shared_event_tick(p_tournament uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   -- Uncontested local evidence may be auto-confirmed only under a new,
   -- explicitly agreed review-timeout rule. It is not sensor verification.
   if t.race_rules ? 'reviewHours' then
     update private.athlth_shared_event_scores r set state='approved',auto_approved=true
     where r.tournament_id=t.id and r.candidate_id=slot.candidate_id and r.state='submitted'
       and r.submitted_at+make_interval(hours=>(t.race_rules->>'reviewHours')::integer)<=current_time_at;
     if found then insert into public.athlth_tournament_audit(tournament_id,event,info)
       values(t.id,'exercise_review_timeout',jsonb_build_object('candidate',slot.candidate_id)); end if;
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
      with per_exercise as (
       select d.candidate_id,d.metric,coalesce(c.activity_template_id,c.exercise_id) exercise_id,
              jsonb_object_agg(r.user_id::text,r.score) scores
       from private.athlth_shared_event_scores r
       join private.athlth_single_event_exercise_definitions(t.id) d on d.candidate_id=r.candidate_id
       join public.athlth_tournament_exercise_candidates c on c.id=d.candidate_id
       join public.athlth_tournament_entries e on e.tournament_id=r.tournament_id and e.user_id=r.user_id
       where r.tournament_id=t.id and r.state='approved' and e.response='accepted' and e.removed_at is null
       group by d.candidate_id,d.metric,c.activity_template_id,c.exercise_id
      ), totals as (
       select pts.user_id,sum(pts.points) as points,
              jsonb_object_agg(x.candidate_id::text,x.scores->pts.user_id::text) as scores
       from per_exercise x cross join lateral private.athlth_exercise_points(t.race_rules,x.metric,x.exercise_id,x.scores,athlete_count) pts
       group by pts.user_id
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
end;$function$
;

CREATE OR REPLACE FUNCTION public.athlth_shared_event_state(p_tournament uuid)
 RETURNS TABLE(candidate_id uuid, title text, metric text, target_value numeric, activity text, sort_order integer, opens_at timestamp with time zone, deadline_at timestamp with time zone, user_id uuid, progress text, score numeric, evidence_note text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament;
 if not found or not t.single_event_mode or t.race_rules->>'exerciseScoringVersion' is distinct from '2'
    or not private.athlth_tournament_can_view(t.id) then raise exception 'Competition not accessible'; end if;
 return query select d.candidate_id,d.title,d.metric,d.target_value,d.activity,d.sort_order,
  s.opens_at,s.deadline_at,e.user_id,case when r.state='approved' and r.auto_approved then 'auto_approved' else coalesce(r.state,'pending') end,
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
end;$function$
;

CREATE OR REPLACE FUNCTION private.athlth_process_measured_matches()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s record; m public.athlth_tournament_matches%rowtype; raw_scores jsonb; hp numeric; ap numeric; htotal numeric; atotal numeric; n integer:=0; d record;
begin
 for s in select x.*,t.race_rules from public.athlth_tournament_match_exercises x
   join public.athlth_tournaments t on t.id=x.tournament_id
   join public.athlth_tournament_matches y on y.id=x.match_id
   where t.status='active' and t.race_rules ? 'scoringMode' and x.state='pending'
      and y.status='scheduled' and y.phase<>'warmup' and y.away_id is not null
      and x.scheduled_at<=clock_timestamp()
      and (x.deadline_at<=clock_timestamp() or
        (t.race_rules ? 'reviewHours' and exists(select 1 from public.athlth_tournament_exercise_completions r where r.match_exercise_id=x.id and r.review_status='submitted' and r.submitted_at+make_interval(hours=>(t.race_rules->>'reviewHours')::integer)<=clock_timestamp())) or
        (select count(*) from public.athlth_tournament_exercise_completions r where r.match_exercise_id=x.id and r.review_status='approved' and r.measured_score is not null)=2)
   order by x.deadline_at,x.id for update of x skip locked
 loop
   select * into m from public.athlth_tournament_matches where id=s.match_id for update;
   if not found or m.status<>'scheduled' then continue; end if;
   if s.race_rules ? 'reviewHours' then
     update public.athlth_tournament_exercise_completions r set review_status='approved',auto_approved=true,approved_at=clock_timestamp(),approved_by=null
     where r.match_exercise_id=s.id and r.review_status='submitted' and r.measured_score is not null
       and r.submitted_at+make_interval(hours=>(s.race_rules->>'reviewHours')::integer)<=clock_timestamp();
     if found then insert into public.athlth_tournament_audit(tournament_id,event,info)
       values(s.tournament_id,'exercise_review_timeout',jsonb_build_object('slot',s.id)); end if;
   end if;
   if exists(select 1 from public.athlth_tournament_exercise_completions r where r.match_exercise_id=s.id and r.review_status='submitted') then continue; end if;
   if s.deadline_at>clock_timestamp() and (select count(*) from public.athlth_tournament_exercise_completions r where r.match_exercise_id=s.id and r.review_status='approved' and r.measured_score is not null)<2 then continue; end if;
   select f.metric,coalesce(c.activity_template_id,c.exercise_id) as exercise_id into d
   from private.athlth_single_event_exercise_definitions(s.tournament_id) f
   join public.athlth_tournament_exercise_candidates c on c.id=f.candidate_id
   where f.candidate_id=s.candidate_id;
   if not found then raise exception 'Missing exercise measurement definition'; end if;
   select coalesce(jsonb_object_agg(r.user_id::text,r.measured_score),'{}') into raw_scores
    from public.athlth_tournament_exercise_completions r where r.match_exercise_id=s.id
      and r.user_id in (m.home_id,m.away_id) and r.review_status='approved' and r.measured_score is not null;
   select coalesce(max(pts.points) filter(where pts.user_id=m.home_id),0),
          coalesce(max(pts.points) filter(where pts.user_id=m.away_id),0) into hp,ap
   from private.athlth_exercise_points(s.race_rules,d.metric,d.exercise_id,raw_scores,2) pts;
   update public.athlth_tournament_match_exercises set
     home_points=hp,away_points=ap,state=case when (select count(*) from jsonb_object_keys(raw_scores))=2 then 'completed'
       when raw_scores='{}'::jsonb then 'disputed' else 'walkover' end,
     winner_id=case when hp>ap then m.home_id when ap>hp then m.away_id else null end,
     resolved_at=clock_timestamp() where id=s.id;
   if not exists(select 1 from public.athlth_tournament_match_exercises x where x.match_id=m.id and x.state='pending') then
     select coalesce(sum(x.home_points),0),coalesce(sum(x.away_points),0) into htotal,atotal
       from public.athlth_tournament_match_exercises x where x.match_id=m.id;
     update public.athlth_tournament_matches set home_score=htotal,away_score=atotal,
       status=case when htotal=atotal and (m.phase in ('cup','playoff') or htotal=0) then 'disputed' else 'confirmed' end,
       confirmed_at=case when htotal=atotal and (m.phase in ('cup','playoff') or htotal=0) then null else clock_timestamp() end,
       proposed_by=null,confirmed_by=null,evidence_note='Calculated from approved exercise measurements'
       where id=m.id;
     if not (htotal=atotal and (m.phase in ('cup','playoff') or htotal=0)) then
       perform private.athlth_tournament_advance(s.tournament_id);
     end if;
   end if;
   n:=n+1;
 end loop;
 return n;
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
    if exists(select 1 from public.athlth_tournaments t where t.id=v_match.tournament_id and t.race_rules ? 'scoringMode') and v_match.phase<>'warmup' then
      -- A knockout tie is resolved by a separately performed, mutually
      -- confirmed tiebreak; no arbitrary winner or overwrite of a live match.
      if v_match.status<>'disputed' or v_match.phase not in ('cup','playoff')
         or v_match.home_score is null or v_match.home_score is distinct from v_match.away_score
         or exists(select 1 from public.athlth_tournament_match_exercises s where s.match_id=v_match.id and s.state='pending')
         or length(btrim(coalesce(p_evidence,'')))<10
      then raise exception 'Match scores are calculated from approved exercise measurements'; end if;
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
        values(v_match.tournament_id,v_user,'knockout_tiebreak_proposed',jsonb_build_object('match',v_match.id,'previous_home_points',v_match.home_score,'previous_away_points',v_match.away_score));
    end if;
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
