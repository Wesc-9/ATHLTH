
-- All four formats use the same pure points function. Original measurements
-- remain unchanged. A handicap is an agreed percentage advantage, not a
-- sensor claim. Goals and weights are keyed by stable exercise library ID.
create or replace function private.athlth_exercise_points(p_rules jsonb,p_metric text,p_exercise uuid,p_scores jsonb,p_athlete_count integer)
returns table(user_id uuid,points numeric)
language sql immutable set search_path='' as $fn$
 with cfg as (
   select coalesce(p_rules->>'scoringMode','ranking') mode,
      coalesce((p_rules->>'pointsPerExercise')::integer,1) unit,
      coalesce((p_rules->'exerciseWeights'->>p_exercise::text)::integer,1) weight,
      (p_rules->'scoringGoals'->>p_exercise::text)::numeric goal
 ), adjusted as (
   select s.key::uuid athlete,
     round(s.value::numeric * (1 + case when p_metric='distance' then -1 else 1 end *
      coalesce((p_rules->'handicapPercentages'->>s.key)::numeric,0)/100),6) value
   from jsonb_each_text(coalesce(p_scores,'{}'::jsonb)) s
 ), ordered as (
   select a.*,c.*,rank() over(order by case when c.mode='closest' then abs(a.value-c.goal)
       when p_metric='distance' then a.value else -a.value end) placement
   from adjusted a cross join cfg c
 )
 select athlete, weight*unit*case mode
   when 'completion' then 1
   when 'target' then case when goal is not null and
     (case when p_metric='distance' then value<=goal else value>=goal end) then 1 else 0 end
   when 'winner' then case when placement=1 then 1 else 0 end
   when 'closest' then case when goal is not null and placement=1 then 1 else 0 end
   else greatest(0,p_athlete_count-placement+1)
 end::numeric
 from ordered;
$fn$;
revoke all on function private.athlth_exercise_points(jsonb,text,uuid,jsonb,integer) from public,anon,authenticated;

-- Typed measurements for round-robin and knockout fixtures.
alter table public.athlth_tournament_exercise_completions add column if not exists measured_score numeric;
alter table public.athlth_tournament_match_exercises add column if not exists home_points numeric, add column if not exists away_points numeric;

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
        or not coalesce(p_setup->'selectedExerciseIDs','[]'::jsonb) ? g.key)
   then raise exception 'Invalid exercise goal'; end if;
   if exists(select 1 from jsonb_each(coalesce(p_setup->'raceRules'->'exerciseWeights','{}')) w
     where jsonb_typeof(w.value)<>'number' or (w.value #>> '{}')::numeric not between 1 and 5
        or (w.value #>> '{}')::numeric<>trunc((w.value #>> '{}')::numeric)
        or not coalesce(p_setup->'selectedExerciseIDs','[]'::jsonb) ? w.key)
   then raise exception 'Invalid exercise weight'; end if;
   if p_setup->'raceRules'->>'scoringMode' in ('target','closest') and
      (not (p_setup ? 'selectedExerciseIDs') or exists(
         select 1 from jsonb_array_elements_text(p_setup->'selectedExerciseIDs') x(id)
         where not coalesce(p_setup->'raceRules'->'scoringGoals','{}'::jsonb) ? x.id))
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
    if v_t.race_rules ? 'scoringMode' and exists (
       select 1 from private.athlth_single_event_exercise_definitions(p_tournament) d
       join public.athlth_tournament_exercise_candidates c on c.id=d.candidate_id
       where d.metric not in ('distance','duration','repetitions','time') or
         (v_t.race_rules->>'scoringMode' in ('target','closest') and
          not coalesce(v_t.race_rules->'scoringGoals','{}') ? coalesce(c.activity_template_id,c.exercise_id)::text)
    ) then raise exception 'Exercise does not have a supported measurement or goal'; end if;
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

CREATE OR REPLACE FUNCTION private.athlth_tournament_record_completion(p_match_exercise uuid, p_evidence_note text, p_source_workout uuid DEFAULT NULL::uuid)
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

revoke all on function private.athlth_tournament_record_completion(uuid,text,uuid) from public,anon,authenticated;
create or replace function public.athlth_tournament_complete_exercise(p_match_exercise uuid,p_evidence_note text,p_source_workout uuid default null)
returns void language plpgsql security definer set search_path='' as $fn$
begin
 if exists(select 1 from public.athlth_tournament_match_exercises s join public.athlth_tournaments t on t.id=s.tournament_id
   where s.id=p_match_exercise and t.race_rules ? 'scoringMode') then
   raise exception 'Submit a measured result with the updated ATHLTH app';
 end if;
 perform private.athlth_tournament_record_completion(p_match_exercise,p_evidence_note,p_source_workout);
end;$fn$;
create or replace function public.athlth_tournament_submit_measured_exercise(p_match_exercise uuid,p_score numeric,p_evidence_note text)
returns void language plpgsql security definer set search_path='' as $fn$
declare s public.athlth_tournament_match_exercises%rowtype; t public.athlth_tournaments%rowtype; d record; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into s from public.athlth_tournament_match_exercises where id=p_match_exercise for update;
 if not found then raise exception 'Exercise not found'; end if;
 select * into t from public.athlth_tournaments where id=s.tournament_id;
 if not (t.race_rules ? 'scoringMode') or t.proof_mode<>'opponent' then raise exception 'Measured scoring not enabled'; end if;
 select * into d from private.athlth_single_event_exercise_definitions(t.id) where candidate_id=s.candidate_id;
 if not found or d.metric not in ('distance','duration','repetitions','time')
    or p_score is null or p_score not between 0 and 100000000
    or (d.metric='distance' and p_score<=0) or (d.metric='repetitions' and p_score<>trunc(p_score))
 then raise exception 'Invalid measured result'; end if;
 if exists(select 1 from public.athlth_tournament_exercise_completions r where r.match_exercise_id=s.id and r.user_id=actor and r.review_status<>'disputed')
 then raise exception 'Result already submitted'; end if;
 -- A rejected result can be corrected during the original submission window.
 delete from public.athlth_tournament_exercise_completions r where r.match_exercise_id=s.id and r.user_id=actor and r.review_status='disputed';
 perform private.athlth_tournament_record_completion(s.id,p_evidence_note,null);
 update public.athlth_tournament_exercise_completions r set measured_score=p_score where r.match_exercise_id=s.id and r.user_id=actor;
 if not found then raise exception 'Measurement was not saved'; end if;
end;$fn$;
revoke all on function public.athlth_tournament_submit_measured_exercise(uuid,numeric,text) from public,anon,authenticated;
grant execute on function public.athlth_tournament_submit_measured_exercise(uuid,numeric,text) to authenticated;

CREATE OR REPLACE FUNCTION public.athlth_tournament_review_exercise(p_match_exercise uuid, p_athlete uuid, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and review_status='submitted'
    and (measured_score is not null or not exists(select 1 from public.athlth_tournaments t where t.id=v_slot.tournament_id and t.race_rules ? 'scoringMode'));
 if not found then raise exception 'No pending workout proof to review'; end if;
 if not p_approve and not exists(select 1 from public.athlth_tournaments t where t.id=v_slot.tournament_id and t.race_rules ? 'scoringMode') then
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
$function$
;

CREATE OR REPLACE FUNCTION private.athlth_competition_process_exercise_deadlines()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_slot record;
 v_match public.athlth_tournament_matches%rowtype;
 v_home boolean;v_away boolean;v_submitted boolean;
 v_home_points integer;v_away_points integer;v_remaining integer;
 v_count integer:=0;
begin
 for v_slot in
   select e.id,e.match_id,e.tournament_id,e.deadline_at
   from public.athlth_tournament_match_exercises e
   join public.athlth_tournaments t on t.id=e.tournament_id
   where e.state='pending' and e.deadline_at<=clock_timestamp()
     and t.status='active' and t.competition_settings_applied and not (t.race_rules ? 'scoringMode')
   order by e.deadline_at,e.id
   for update of e skip locked
 loop
   select * into v_match from public.athlth_tournament_matches
   where id=v_slot.match_id for update;
   if not found or v_match.status='confirmed' then
     update public.athlth_tournament_match_exercises
     set state='completed',resolved_at=clock_timestamp()
     where id=v_slot.id;
     continue;
   end if;
   if v_match.status='proposed' then continue; end if;
   select exists(
       select 1 from public.athlth_tournament_exercise_completions c
       where c.match_exercise_id=v_slot.id
         and c.user_id=v_match.home_id and c.review_status='approved'
   ) into v_home;
   select exists(
       select 1 from public.athlth_tournament_exercise_completions c
       where c.match_exercise_id=v_slot.id
         and c.user_id=v_match.away_id and c.review_status='approved'
   ) into v_away;
   select exists(
       select 1 from public.athlth_tournament_exercise_completions c
       where c.match_exercise_id=v_slot.id and c.review_status='submitted'
   ) into v_submitted;
   if v_submitted and not (v_home and v_away) then
     -- An on-time submission under review must not be scored zero.
     continue;
   end if;
   update public.athlth_tournament_match_exercises
     set state=case
            when v_home and v_away then 'completed'
            when v_home or v_away then 'walkover'
            else 'disputed' end,
         winner_id=case when v_home and not v_away
                 then v_match.home_id
                 when v_away and not v_home then v_match.away_id
                 else null end,
         resolved_at=clock_timestamp()
   where id=v_slot.id;
   insert into public.athlth_tournament_audit(tournament_id,event,info)
   values(v_slot.tournament_id,'competition_exercise_scored',
      jsonb_build_object('slot',v_slot.id,
          'home_points',case when v_home then 1 else 0 end,
          'away_points',case when v_away then 1 else 0 end,
          'deadline',v_slot.deadline_at));
   select count(*) into v_remaining
   from public.athlth_tournament_match_exercises ex
   where ex.match_id=v_match.id and ex.state='pending';
   if v_remaining>0 then continue; end if;
   select count(*) into v_home_points
   from public.athlth_tournament_match_exercises ex
   join public.athlth_tournament_exercise_completions c
     on c.match_exercise_id=ex.id
   where ex.match_id=v_match.id and c.user_id=v_match.home_id
     and c.review_status='approved';
   select count(*) into v_away_points
   from public.athlth_tournament_match_exercises ex
   join public.athlth_tournament_exercise_completions c
     on c.match_exercise_id=ex.id
   where ex.match_id=v_match.id and c.user_id=v_match.away_id
     and c.review_status='approved';
   if v_home_points=v_away_points and
      (v_match.phase in ('cup','playoff') or v_home_points=0) then
     update public.athlth_tournament_matches
       set status='disputed',home_score=v_home_points,
           away_score=v_away_points
     where id=v_match.id and status='scheduled';
     -- No random winner if both athletes miss or a cup is tied.
   else
     update public.athlth_tournament_matches
       set status='confirmed',home_score=v_home_points,
           away_score=v_away_points,confirmed_at=clock_timestamp(),
           proposed_by=null,confirmed_by=null,
           evidence_note='Approved exercise results and zero for missed deadlines'
     where id=v_match.id and status='scheduled';
     if found then
       perform private.athlth_tournament_advance(v_slot.tournament_id);
     end if;
   end if;
   v_count:=v_count+1;
 end loop;
 return v_count;
end;
$function$
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
      raise exception 'Match scores are calculated from approved exercise measurements';
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

CREATE OR REPLACE FUNCTION public.athlth_competition_submit_local_measurement(p_tournament uuid, p_user uuid, p_target uuid, p_workout uuid, p_score numeric, p_started timestamp with time zone, p_ended timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
   if exists(select 1 from public.athlth_tournaments t where t.id=p_tournament and t.race_rules ? 'scoringMode') then
     perform public.athlth_tournament_submit_measured_exercise(p_target,p_score,note);
   else
     perform public.athlth_tournament_complete_exercise(p_target,note,null);
   end if;
 end if;
 return true;
end;$function$
;

-- Resolve measured fixtures without trusting client-supplied match totals.
create or replace function private.athlth_process_measured_matches()
returns integer language plpgsql security definer set search_path='' as $fn$
declare s record; m public.athlth_tournament_matches%rowtype; raw_scores jsonb; hp numeric; ap numeric; htotal numeric; atotal numeric; n integer:=0; d record;
begin
 for s in select x.*,t.race_rules from public.athlth_tournament_match_exercises x
   join public.athlth_tournaments t on t.id=x.tournament_id
   join public.athlth_tournament_matches y on y.id=x.match_id
   where t.status='active' and t.race_rules ? 'scoringMode' and x.state='pending'
      and y.status='scheduled' and y.phase<>'warmup' and y.away_id is not null
      and x.scheduled_at<=clock_timestamp()
      and (x.deadline_at<=clock_timestamp() or
        (select count(*) from public.athlth_tournament_exercise_completions r where r.match_exercise_id=x.id and r.review_status='approved' and r.measured_score is not null)=2)
   order by x.deadline_at,x.id for update of x skip locked
 loop
   select * into m from public.athlth_tournament_matches where id=s.match_id for update;
   if not found or m.status<>'scheduled' then continue; end if;
   if exists(select 1 from public.athlth_tournament_exercise_completions r where r.match_exercise_id=s.id and r.review_status='submitted') then continue; end if;
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
end;$fn$;
revoke all on function private.athlth_process_measured_matches() from public,anon,authenticated;
select cron.schedule('athlth-competition-measured-matches','* * * * *','select private.athlth_process_measured_matches()');
