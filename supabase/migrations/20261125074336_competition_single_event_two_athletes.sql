-- Allow an organizer and one opponent in single events. Preserve existing
-- permissions, readiness, invitation, scoring and race verification rules.
CREATE OR REPLACE FUNCTION public.athlth_tournament_create_competition(p_title text, p_format text, p_club uuid, p_season uuid, p_group_size integer, p_qualifiers integer, p_invitees uuid[], p_warmup_titles text[], p_exercise_mode text, p_exercise_count integer, p_proposals_close timestamp with time zone, p_votes_close timestamp with time zone, p_approve_player_changes boolean, p_allowed_activities text[], p_rules_authority text, p_cadence_days integer, p_completion_hours integer, p_rotation_mode text, p_rest_weekdays integer[], p_proof_mode text, p_public_results boolean, p_allow_extensions boolean, p_win_points integer, p_draw_points integer, p_setup jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v uuid; v_exercise record; v_count integer:=0;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
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
     and (p_format<>'league' or coalesce(array_length(p_invitees,1),0)<1))
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
    if v_t.single_event_mode and v_count<2 then
        raise exception 'A single event requires at least two ready athletes';
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
       >=case when t.format='cup' then 4 when t.single_event_mode then 2 else 2 end
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
         accepted_count<(case when t.format='cup' then 4 when t.single_event_mode then 2 else 2 end) then
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
       and e.removed_at is null)<(case when new.format='cup' then 4 when new.single_event_mode then 2 else 2 end) then
    raise exception 'Liga requires two; cup requires four accepted athletes';
 end if;
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

CREATE OR REPLACE FUNCTION public.athlth_tournament_create_simple_event(p_title text, p_format text, p_activity text, p_invitees uuid[], p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_owner uuid := auth.uid();
    v_id uuid;
    v_template uuid;
    v_title text;
begin
    if v_owner is null then raise exception 'Sign in required'; end if;
    if p_format<>'league' or
       p_activity not in ('running','walking','strength') or
       (coalesce(array_length(p_invitees,1),0)<1
        or coalesce(array_length(p_invitees,1),0)>20) or
       length(btrim(coalesce(p_title,''))) not between 3 and 80 then
        raise exception 'Invalid Basic competition settings';
    end if;
    if p_starts_at is not null and
       (p_starts_at<clock_timestamp()-interval '1 minute' or
        p_starts_at>clock_timestamp()+interval '366 days') then
       raise exception 'Choose a future start date';
    end if;
    v_title:=case p_activity
      when 'running' then 'Løp 5 km'
      when 'walking' then 'Gå 5 km'
      when 'strength' then 'Knebøy – flest repetisjoner'
    end;
    select id into v_template
    from public.athlth_tournament_activity_templates
    where title=v_title and activity_type=p_activity and is_active
    order by id limit 1;
    if v_template is null then
       raise exception 'Default activity is currently unavailable';
    end if;

    v_id:=public.athlth_tournament_create_competition(
       p_title,p_format,null::uuid,null::uuid,4,2,
       p_invitees,ARRAY[]::text[],'owner',1,null::timestamptz,
       null::timestamptz,false,ARRAY[p_activity],'owner',
       7,48,'all',ARRAY[]::integer[],'opponent',
       false,true,3,1,
       jsonb_build_object(
          'singleEventMode',true,
          'raceRules',jsonb_build_object('discipline',
              case when p_activity='strength' then 'workout' else 'distance' end,
              'targetDistanceMeters',5000,'countdownSeconds',10,
              'recordingDevice','any','sprintMode','mass_start'),
          'startsAt',p_starts_at,'startMode',case when p_starts_at is null then 'when_ready' else 'scheduled' end,
          'unlock','interval',
          'every',7,'unit','day','invitationPermission','admin',
          'joinApproval','admin','allowed','','prohibited','',
          'firstPrize','','secondPrize','','thirdPrize','',
          'loserConsequence',''
       )
    );
    insert into public.athlth_tournament_exercise_candidates(
        tournament_id,activity_template_id,suggested_by,selected_position
    ) values(v_id,v_template,v_owner,1);
    update public.athlth_tournaments
       set simple_mode=true,exercise_selection_finalized_at=clock_timestamp()
       where id=v_id;
    -- Creator explicitly chose Basic defaults when pressing Publish.
    update public.athlth_tournament_entries
       set agreed_rule_version=1,agreed_rules_at=clock_timestamp(),
           is_ready=true,ready_at=clock_timestamp()
       where tournament_id=v_id and user_id=v_owner and response='accepted';
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(v_id,v_owner,'simple_setup_completed',
       jsonb_build_object('activity',p_activity,'exercise',v_template));
    return v_id;
end;
$function$
;
revoke all on function public.athlth_tournament_create_simple_event(text,text,text,uuid[],timestamptz)
 from public,anon;
grant execute on function public.athlth_tournament_create_simple_event(text,text,text,uuid[],timestamptz)
 to authenticated;
