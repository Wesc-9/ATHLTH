-- Arena evidence protocol v2.
-- Every timed-run submission must carry measured full-workout distance.
-- Server validates source and interval consistency, rejects future workouts,
-- and never treats caller-provided metrics as independently attested.
alter table public.arena_workout_evidence
 add column if not exists reported_distance_meters numeric(12,3);
alter table public.arena_workout_evidence
 add column if not exists verification_level text not null default 'participant_reported'
 check (verification_level = 'participant_reported');
comment on column public.arena_workout_evidence.verification_level is
 'Participant-shared client workout metrics; neither Apple Health nor GPS is independently attested.';
comment on table public.arena_workout_evidence is
 'Only minimal user-consented workout metadata. Results are untrusted until participant consensus.';

create or replace function private.arena_share_evidence_v2_impl(
 p_round uuid,p_source_workout uuid,p_source text,p_activity text,
 p_started timestamptz,p_ended timestamptz,p_metric_type text,
 p_metric numeric,p_distance numeric
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare
 v_series public.arena_series%rowtype;
 v_round public.arena_round_proposals%rowtype;
 v_slot uuid;
 v_actor uuid := (select auth.uid());
 v_id uuid;
 v_wall_seconds numeric;
 v_target numeric;
 v_min_seconds numeric;
 v_max_seconds numeric;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 select * into v_round from public.arena_round_proposals where id=p_round;
 if not found then raise exception 'Unknown round'; end if;
 select * into v_series from public.arena_series where id=v_round.series_id;
 if v_series.status<>'active' or v_series.starts_at is null or v_series.ends_at is null then
   raise exception 'Round is not active';
 end if;
 if p_started is null or p_ended is null or p_started < v_series.starts_at
   or p_ended > v_series.ends_at or p_ended > now() + interval '2 minutes'
   or p_started > now() or p_ended<=p_started
   or p_ended-p_started>interval '24 hours' then
   raise exception 'Workout must be finished inside the competition window';
 end if;
 v_wall_seconds := extract(epoch from (p_ended-p_started));
 select slot_id into v_slot from public.arena_series_members
  where series_id=v_series.id and user_id=v_actor and response='accepted';
 if v_slot is null then raise exception 'Not a participating athlete'; end if;
 if p_source_workout is null or p_source not in ('iphone','athlth_strength','apple_health')
   or p_activity not in ('running','walking','strength')
   or p_metric is null or p_metric<=0 or p_metric>1000000000
   or (p_distance is not null and (p_distance<=0 or p_distance>500000)) then
   raise exception 'Invalid workout evidence fields';
 end if;
 if v_round.template in ('fastest5K','fastest1K') then
   if v_round.template='fastest5K' then
     v_target := 5000;
     v_min_seconds := 150;
     v_max_seconds := 18000;
   else
     v_target := 1000;
     v_min_seconds := 60;
     v_max_seconds := 7200;
   end if;
   if p_activity<>'running' or p_metric_type<>'elapsed_seconds'
     or p_distance is null or abs(p_distance-v_target)>v_target*0.02
     or p_metric < case when v_target=5000 then 150 else 60 end
     or p_metric > case when v_target=5000 then 18000 else 7200 end
     or p_metric > v_wall_seconds+120 then
     raise exception 'Timed run must have matching full-workout distance and elapsed time';
   end if;
 elsif v_round.template='mostDistance' then
   if p_activity not in ('running','walking') or p_metric_type<>'distance_meters'
     or p_distance is null or abs(p_distance-p_metric)>1
     or p_metric<300 or v_wall_seconds<300 then
     raise exception 'Distance and duration do not match a completed workout';
   end if;
 elsif v_round.template='mostWorkouts' then
   if p_activity not in ('running','walking','strength')
      or p_metric_type<>'completed_workout' or p_metric<>1
      or v_wall_seconds<600 then
     raise exception 'Completed workouts must last at least ten minutes';
   end if;
 else
   raise exception 'This template requires manual review';
 end if;

 insert into public.arena_workout_evidence(
  series_id,round_id,slot_id,user_id,source_workout_id,
  source,activity_type,started_at,ended_at,
  metric_type,metric_value,reported_distance_meters,verification_level
 ) values(
  v_series.id,p_round,v_slot,v_actor,p_source_workout,
  p_source,p_activity,p_started,p_ended,
  p_metric_type,p_metric,p_distance,'participant_reported'
 ) returning id into v_id;
 return v_id;
end;
$$;

create or replace function public.arena_share_evidence_v2(
 p_round uuid,p_source_workout uuid,p_source text,p_activity text,
 p_started timestamptz,p_ended timestamptz,p_metric_type text,
 p_metric numeric,p_distance numeric
) returns uuid language sql security invoker
set search_path=pg_catalog,public,private as $$
 select private.arena_share_evidence_v2_impl(
  p_round,p_source_workout,p_source,p_activity,
  p_started,p_ended,p_metric_type,p_metric,p_distance
 );
$$;
-- Retire v1 exposed procedure, which did not carry measured run distance.
revoke all on function public.arena_share_evidence(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric
) from public,anon,authenticated;
revoke all on function private.arena_share_evidence_impl(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric
) from public,anon,authenticated;
revoke all on function public.arena_share_evidence_v2(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric,numeric
) from public,anon;
revoke all on function private.arena_share_evidence_v2_impl(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric,numeric
) from public,anon;
grant execute on function public.arena_share_evidence_v2(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric,numeric
) to authenticated;
grant execute on function private.arena_share_evidence_v2_impl(
 uuid,uuid,text,text,timestamptz,timestamptz,text,numeric,numeric
) to authenticated;
