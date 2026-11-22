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
