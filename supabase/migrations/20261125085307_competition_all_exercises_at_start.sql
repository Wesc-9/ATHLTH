alter table public.athlth_tournaments drop constraint athlth_tournaments_release_mode_check;
alter table public.athlth_tournaments add constraint athlth_tournaments_release_mode_check check (release_mode in ('interval','everyone_finished','all_at_start'));
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

CREATE OR REPLACE FUNCTION private.athlth_shared_event_initialize()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cap timestamptz:=nullif(new.race_rules->>'competitionEndsAt','')::timestamptz;
begin
 if new.status='active' and old.status is distinct from new.status and new.single_event_mode
    and new.race_rules->>'exerciseScoringVersion'='2' then
   insert into private.athlth_shared_event_slots(tournament_id,candidate_id,sort_order,opens_at,deadline_at)
   select new.id,d.candidate_id,d.sort_order,
      case when new.release_mode in ('interval','all_at_start') or d.sort_order=1
           then new.race_signal_at+(case when new.release_mode='all_at_start' then 0 else d.sort_order-1 end)*private.athlth_shared_event_gap(new.release_unit,new.release_every) end,
      case when new.release_mode in ('interval','all_at_start') or d.sort_order=1
           then least(cap,new.race_signal_at+(case when new.release_mode='all_at_start' then 0 else d.sort_order-1 end)*private.athlth_shared_event_gap(new.release_unit,new.release_every)+make_interval(hours=>new.completion_hours)) end
   from private.athlth_single_event_exercise_definitions(new.id) d;
 end if;
 return new;
end;$function$
;

CREATE OR REPLACE FUNCTION private.athlth_competition_slot_schedule()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_t public.athlth_tournaments%rowtype;
 v_match public.athlth_tournament_matches%rowtype;
 v_gap interval; v_start timestamptz;
begin
 select * into v_t from public.athlth_tournaments where id=new.tournament_id;
 if not found or not v_t.competition_settings_applied or new.position<1
 then return new; end if;
 select * into v_match from public.athlth_tournament_matches
 where id=new.match_id;
 if not found or v_match.phase='warmup' then return new; end if;
 if v_t.release_mode='all_at_start' then
   v_start:=v_match.scheduled_at;
 elsif v_t.release_mode='everyone_finished' and new.position>1 then
   v_start:=timestamptz '2099-12-31 00:00:00+00';
 else
   v_gap:=case v_t.release_unit
     when 'minute' then make_interval(mins=>v_t.release_every)
     when 'hour' then make_interval(hours=>v_t.release_every)
     when 'day' then make_interval(days=>v_t.release_every)
     else make_interval(months=>v_t.release_every)
   end;
   v_start:=v_match.scheduled_at+(new.position-1)*v_gap;
 end if;
 update public.athlth_tournament_match_exercises
 set scheduled_at=v_start,
     deadline_at=v_start+v_t.completion_hours*interval '1 hour'
 where id=new.id;
 return new;
end;
$function$
;
