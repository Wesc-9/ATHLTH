-- Fresh rematches alternate exercise selection; seasons have stable parent identity.
CREATE OR REPLACE FUNCTION public.athlth_tournament_create_competition(p_title text, p_format text, p_club uuid, p_season uuid, p_group_size integer, p_qualifiers integer, p_invitees uuid[], p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer, p_proposals_close timestamp with time zone, p_votes_close timestamp with time zone, p_approve_player_changes boolean, p_allowed_activities text[], p_rules_authority text, p_cadence_days integer, p_completion_hours integer, p_rotation_mode text, p_rest_weekdays integer[], p_proof_mode text, p_public_results boolean, p_allow_extensions boolean, p_win_points integer, p_draw_points integer, p_setup jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v uuid; v_exercise record; v_count integer:=0; previous public.athlth_tournaments%rowtype; parent_id uuid; previous_number integer; selected_ids jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
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
create unique index if not exists athlth_competition_one_continuation on public.athlth_tournaments (((race_rules->>'previousCompetitionID')::uuid)) where race_rules ? 'previousCompetitionID' and status<>'cancelled';
