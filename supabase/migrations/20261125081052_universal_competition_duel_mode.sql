-- All four formats use the same tournament creation and readiness contract.
-- A duel is a private two-person exercise-scored event, not a separate challenge.
create or replace function private.athlth_competition_minimum_athletes(p_format text,p_single boolean,p_race jsonb)
returns integer language sql immutable set search_path='' as $fn$
 select case when p_race->>'duelMode'='true' then 2 when p_format='cup' then 4 when p_single then 3 else 2 end
$fn$;
-- The trigger executes under the existing authenticated start/update path.
grant execute on function private.athlth_competition_minimum_athletes(text,boolean,jsonb) to authenticated;

create or replace function private.athlth_duel_no_extra_entrants()
returns trigger language plpgsql security definer set search_path='' as $fn$
begin
 if exists(select 1 from public.athlth_tournaments t where t.id=new.tournament_id and t.race_rules->>'duelMode'='true') then
    raise exception 'A duel is limited to its original two athletes';
 end if;
 return new;
end;$fn$;
revoke all on function private.athlth_duel_no_extra_entrants() from public,anon,authenticated;
drop trigger if exists athlth_duel_no_extra_entrants on public.athlth_tournament_entries;
create trigger athlth_duel_no_extra_entrants before insert on public.athlth_tournament_entries
 for each row execute function private.athlth_duel_no_extra_entrants();

-- Raw result rows are private to the submitting athlete for duels. The
-- checked RPC supplies the opponent's results once both have submitted.
drop policy if exists single_event_result_private on public.athlth_tournament_single_event_results;
create policy single_event_result_private on public.athlth_tournament_single_event_results
 for select to authenticated using (
 user_id=(select auth.uid()) or exists(select 1 from public.athlth_tournaments t
 where t.id=tournament_id and t.owner_id=(select auth.uid())
 and t.race_rules->>'duelMode' is distinct from 'true'));

CREATE OR REPLACE FUNCTION public.athlth_tournament_create_competition(p_title text, p_format text, p_club uuid, p_season uuid, p_group_size integer, p_qualifiers integer, p_invitees uuid[], p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer, p_proposals_close timestamp with time zone, p_votes_close timestamp with time zone, p_approve_player_changes boolean, p_allowed_activities text[], p_rules_authority text, p_cadence_days integer, p_completion_hours integer, p_rotation_mode text, p_rest_weekdays integer[], p_proof_mode text, p_public_results boolean, p_allow_extensions boolean, p_win_points integer, p_draw_points integer, p_setup jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v uuid; v_exercise record; v_count integer:=0;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_setup->'raceRules'->>'duelMode'='true' and
    (not coalesce((p_setup->>'singleEventMode')::boolean,false)
     or p_format<>'league' or cardinality(coalesce(p_invitees,array[]::uuid[]))<>1
     or p_invitees[1]=auth.uid() or p_invitees[1] is null
     or p_club is not null or p_season is not null
     or p_setup->'raceRules'->>'exerciseScoringVersion' is distinct from '1'
     or coalesce(p_setup->>'unansweredPolicy','cancel')<>'cancel'
     or coalesce(p_setup->>'invitationPermission','admin')<>'admin'
     or coalesce(p_setup->>'joinApproval','admin')<>'admin'
     or p_public_results) then
   raise exception 'Duel requires exactly two private participants and exercise scoring';
 end if;
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

CREATE OR REPLACE FUNCTION private.athlth_competition_auto_start()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; started integer:=0;
begin
 for r in select t.id from public.athlth_tournaments t
   where t.competition_settings_applied and t.status='inviting'
   and t.start_mode in ('when_ready','scheduled')
   and (t.unanswered_policy<>'replace' or t.replacement_until is null)
   and (t.start_mode='when_ready' or (t.planned_starts_at is not null
      and t.planned_starts_at<=clock_timestamp()))
   and t.rules_confirmed_at is not null
   and t.exercise_selection_finalized_at is not null
   and not exists (select 1 from public.athlth_tournament_entries e
       where e.tournament_id=t.id and e.response='invited')
   and not exists (select 1 from public.athlth_tournament_entries e
       where e.tournament_id=t.id and e.response='accepted'
         and (e.is_ready is not true or e.removed_at is not null
              or e.agreed_rule_version is distinct from t.rule_version))
   and (select count(*) from public.athlth_tournament_entries e
       where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null)
       >=private.athlth_competition_minimum_athletes(t.format,t.single_event_mode,t.race_rules)
   order by t.created_at limit 100
 loop
   begin
     perform private.athlth_competition_start_internal(r.id);
     started:=started+1;
   exception when others then
     -- Do not fail the batch; keep the competition waiting for a valid setup.
     raise warning 'Competition automatic start %: %',r.id,sqlerrm;
   end;
 end loop;
 return started;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.athlth_competition_expire_invitations()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t record; expired_count integer; declined_count integer; accepted_count integer;
 pending_count integer; processed integer:=0; now_time timestamptz:=clock_timestamp();
begin
 for t in select x.* from public.athlth_tournaments x
   where x.status='inviting' and x.competition_settings_applied
     and (exists(select 1 from public.athlth_tournament_entries e
       where e.tournament_id=x.id and e.response='invited'
         and e.expires_at<=now_time)
       or (x.unanswered_policy='replace' and x.replacement_until<=now_time)
       or exists(select 1 from public.athlth_tournament_entries refused
          where refused.tournament_id=x.id and refused.response='declined')
       or not exists(select 1 from public.athlth_tournament_entries e
           where e.tournament_id=x.id and e.response='invited'))
   order by x.created_at limit 250
 loop
   -- Same row lock as all start/respond operations. Never cancel an active event.
   perform 1 from public.athlth_tournaments x where x.id=t.id for update;
   if not exists(select 1 from public.athlth_tournaments x
     where x.id=t.id and x.status='inviting') then continue; end if;
   update public.athlth_tournament_entries e
    set response='expired',responded_at=now_time
    where e.tournament_id=t.id and e.response='invited'
      and e.expires_at<=now_time;
   get diagnostics expired_count=row_count;
   if expired_count>0 then
     insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
     values(t.id,t.owner_id,'invitation_expired',
       jsonb_build_object('count',expired_count));
   end if;
   select count(*) into declined_count from public.athlth_tournament_entries e
     where e.tournament_id=t.id and e.response in ('declined','expired');
   select count(*) into accepted_count from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null;
   select count(*) into pending_count from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.response='invited' and e.removed_at is null;
   if pending_count=0 and accepted_count<=1 then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'cancelled',jsonb_build_object('reason','no_acceptances'));
      processed:=processed+1;
   elsif declined_count>0 and t.unanswered_policy='cancel' then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'cancelled',jsonb_build_object('reason','invitation_expired'));
      processed:=processed+1;
   elsif declined_count>0 and t.unanswered_policy='replace'
      and t.replacement_until is null and not t.replacement_resolved then
      update public.athlth_tournaments set replacement_until=
        now_time+make_interval(days=>t.invitation_days) where id=t.id;
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'replacement_window_opened',
        jsonb_build_object('days',t.invitation_days));
      processed:=processed+1;
   elsif pending_count=0 and t.unanswered_policy='continue' and
         accepted_count<(private.athlth_competition_minimum_athletes(t.format,t.single_event_mode,t.race_rules)) then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      processed:=processed+1;
   elsif t.unanswered_policy='replace' and t.replacement_until<=now_time then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'cancelled',jsonb_build_object('reason','replacement_deadline'));
      processed:=processed+1;
   end if;
 end loop;
 return processed;
end;$function$
;

CREATE OR REPLACE FUNCTION private.athlth_competition_start_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
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

CREATE OR REPLACE FUNCTION public.athlth_tournament_single_event_exercise_details(p_tournament uuid)
 RETURNS TABLE(user_id uuid, exercise_scores jsonb, evidence_note text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.athlth_tournaments%rowtype; actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament;
 if not found or not t.single_event_mode or t.race_rules->>'exerciseScoringVersion' is distinct from '1'
    or not private.athlth_tournament_can_view(t.id) then raise exception 'Competition not accessible'; end if;
 return query select r.user_id,r.exercise_scores,
   case when r.user_id=actor or t.owner_id=actor or t.race_rules->>'duelMode'='true' then r.evidence_note else null end
 from public.athlth_tournament_single_event_results r
 join public.athlth_tournament_entries e on e.tournament_id=r.tournament_id and e.user_id=r.user_id
 where r.tournament_id=t.id and r.exercise_scores is not null
   and e.response='accepted' and e.removed_at is null
   and (r.user_id=actor or
     (t.race_rules->>'duelMode' is distinct from 'true' and t.owner_id=actor) or
     (t.race_rules->>'duelMode'='true' and exists(select 1 from public.athlth_tournament_entries own
        where own.tournament_id=t.id and own.user_id=actor and own.response='accepted' and own.removed_at is null)
       and exists(select 1 from public.athlth_tournament_single_event_results own
        where own.tournament_id=t.id and own.user_id=actor and own.review_status in ('submitted','approved'))) or
     (t.status='completed' and r.review_status='approved'));
end;$function$
;
