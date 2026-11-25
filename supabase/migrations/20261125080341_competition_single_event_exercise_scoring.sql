
-- Exercise-based scoring for new workout-based single events.
alter table public.athlth_tournament_single_event_results add column if not exists exercise_scores jsonb;

create or replace function private.athlth_single_event_exercise_definitions(p_tournament uuid)
returns table(candidate_id uuid,title text,metric text,target_value numeric,activity text,sort_order integer)
language sql stable security invoker set search_path='' as $fn$
 select c.id,coalesce(a.title,e.name),coalesce(a.metric,'repetitions'),a.target_value,
        coalesce(a.activity_type,'strength'),c.selected_position::integer
 from public.athlth_tournament_exercise_candidates c
 left join public.athlth_tournament_activity_templates a on a.id=c.activity_template_id
 left join public.exercise_catalog e on e.id=c.exercise_id
 where c.tournament_id=p_tournament and c.selected_position is not null
   and (a.id is not null or e.id is not null)
 order by c.selected_position,c.id;
$fn$;
revoke all on function private.athlth_single_event_exercise_definitions(uuid) from public,anon,authenticated;

create or replace function public.athlth_tournament_single_event_exercises(p_tournament uuid)
returns table(candidate_id uuid,title text,metric text,target_value numeric,activity text,sort_order integer)
language plpgsql stable security definer set search_path='' as $fn$
begin
 if auth.uid() is null or not private.athlth_tournament_can_view(p_tournament)
    or not exists(select 1 from public.athlth_tournaments t where t.id=p_tournament
       and t.single_event_mode and t.race_rules->>'exerciseScoringVersion'='1') then
    raise exception 'Competition not accessible';
 end if;
 return query select d.* from private.athlth_single_event_exercise_definitions(p_tournament) d;
end;$fn$;
revoke all on function public.athlth_tournament_single_event_exercises(uuid) from public,anon,authenticated;
grant execute on function public.athlth_tournament_single_event_exercises(uuid) to authenticated;

create or replace function public.athlth_tournament_single_event_exercise_details(p_tournament uuid)
returns table(user_id uuid,exercise_scores jsonb,evidence_note text)
language plpgsql stable security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament;
 if not found or not t.single_event_mode or t.race_rules->>'exerciseScoringVersion' is distinct from '1'
    or not private.athlth_tournament_can_view(t.id) then raise exception 'Competition not accessible'; end if;
 return query select r.user_id,r.exercise_scores,
   case when r.user_id=actor or t.owner_id=actor then r.evidence_note else null end
 from public.athlth_tournament_single_event_results r
 join public.athlth_tournament_entries e on e.tournament_id=r.tournament_id and e.user_id=r.user_id
 where r.tournament_id=t.id and r.exercise_scores is not null
   and e.response='accepted' and e.removed_at is null
   and (r.user_id=actor or t.owner_id=actor or (t.status='completed' and r.review_status='approved'));
end;$fn$;
revoke all on function public.athlth_tournament_single_event_exercise_details(uuid) from public,anon,authenticated;
grant execute on function public.athlth_tournament_single_event_exercise_details(uuid) to authenticated;

create or replace function public.athlth_tournament_single_event_submit_exercises(p_tournament uuid,p_scores jsonb,p_evidence text)
returns void language plpgsql security definer set search_path='' as $fn$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
 d record; value_json jsonb; result_value numeric; actual_count integer;
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or not t.single_event_mode or t.status<>'active'
   or t.race_signal_at is null or clock_timestamp()<t.race_signal_at
   or t.race_rules->>'exerciseScoringVersion' is distinct from '1'
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
end;$fn$;
revoke all on function public.athlth_tournament_single_event_submit_exercises(uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.athlth_tournament_single_event_submit_exercises(uuid,jsonb,text) to authenticated;

CREATE OR REPLACE FUNCTION public.athlth_tournament_create_competition(p_title text, p_format text, p_club uuid, p_season uuid, p_group_size integer, p_qualifiers integer, p_invitees uuid[], p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer, p_proposals_close timestamp with time zone, p_votes_close timestamp with time zone, p_approve_player_changes boolean, p_allowed_activities text[], p_rules_authority text, p_cadence_days integer, p_completion_hours integer, p_rotation_mode text, p_rest_weekdays integer[], p_proof_mode text, p_public_results boolean, p_allow_extensions boolean, p_win_points integer, p_draw_points integer, p_setup jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v uuid; v_exercise record; v_count integer:=0;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_setup->'raceRules'->>'exerciseScoringVersion'='1' and
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
     and (p_format<>'league' or coalesce(array_length(p_invitees,1),0)<2))
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
    if v_t.single_event_mode and v_count<3 then
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
        if v_t.race_rules->>'exerciseScoringVersion'='1' and (
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
 if t.race_rules->>'exerciseScoringVersion'='1' then
   raise exception 'Submit individual exercise scores with the updated ATHLTH app';
 end if;
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
    or t.owner_id<>auth.uid() then
    raise exception 'Only the event organizer may review results'; end if;
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

CREATE OR REPLACE FUNCTION public.athlth_tournament_single_event_status(p_tournament uuid)
 RETURNS TABLE(user_id uuid, progress text, score numeric, rank bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.athlth_tournaments%rowtype; all_done boolean;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament;
 if not found or not t.single_event_mode or
    not private.athlth_tournament_can_view(t.id) then
     raise exception 'Competition not accessible'; end if;
 select not exists(select 1 from public.athlth_tournament_entries e
   where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
     and not exists(select 1 from public.athlth_tournament_single_event_results r
       where r.tournament_id=t.id and r.user_id=e.user_id
         and r.review_status='approved'))
 into all_done;
 return query
 with scores as (
  select e.user_id,e.response,e.is_ready,r.review_status,r.reported_score,
    case when t.race_rules->>'discipline'='sprint' and
                   t.race_rules->>'sprintTarget' is distinct from 'duration'
                 or t.race_rules->>'discipline'='distance'
                 or t.race_rules->>'discipline'='laps'
         then true else false end as lower_wins
  from public.athlth_tournament_entries e
  left join public.athlth_tournament_single_event_results r
   on r.tournament_id=e.tournament_id and r.user_id=e.user_id
  where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null
 ), ranked as (
 select x.user_id,
    case when x.review_status='approved' then 'finished'
         when x.review_status='submitted' then 'awaiting_review'
         when x.review_status='rejected' then 'rejected'
         when not x.is_ready then 'not_ready' else 'waiting' end::text as p,
    x.reported_score,
    rank() over (order by
      (case when x.lower_wins then x.reported_score end) asc nulls last,
      (case when not x.lower_wins then x.reported_score end) desc nulls last
    ) as pos
  from scores x)
 select r.user_id,r.p,
  case when t.race_rules->>'exerciseScoringVersion'='1' and not all_done then null
       when all_done or r.user_id=auth.uid() or t.owner_id=auth.uid()
       then r.reported_score else null end,
  case when all_done then r.pos else null end
 from ranked r order by r.pos;
end;$function$
;
