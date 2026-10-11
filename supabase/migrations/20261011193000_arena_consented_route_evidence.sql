-- Arena 2.0 route attempts: a local GPS comparison shared only by explicit consent.
-- Scores are participant-reported and MUST still pass group consensus.
alter table public.arena_workout_evidence
  add column if not exists reported_route_match_percent numeric(5,2);
alter table public.arena_workout_evidence
  drop constraint if exists arena_route_match_reported_percent_check;
alter table public.arena_workout_evidence
  add constraint arena_route_match_reported_percent_check
  check (reported_route_match_percent is null or
         reported_route_match_percent between 0 and 100);

comment on column public.arena_workout_evidence.reported_route_match_percent is
 'Unattested client-calculated route similarity. Not independent GPS verification.';

create or replace function public.arena_share_route_evidence(
 p_round uuid, p_source_workout uuid,
 p_started timestamptz, p_ended timestamptz,
 p_elapsed_seconds numeric, p_distance_meters numeric,
 p_route_match_percent numeric, p_start_gap_meters numeric,
 p_end_gap_meters numeric
) returns uuid language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare
 v_actor uuid := (select auth.uid());
 v_round public.arena_round_proposals%rowtype;
 v_series public.arena_series%rowtype;
 v_slot uuid;
 v_id uuid;
 v_wall_seconds numeric;
 v_target numeric;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 if p_source_workout is null then raise exception 'Workout ID is required'; end if;
 select * into v_round from public.arena_round_proposals where id=p_round;
 if not found or v_round.template<>'fastestRoute'
   or v_round.route_snapshot is null then
   raise exception 'Unknown Arena route round';
 end if;
 select * into v_series from public.arena_series where id=v_round.series_id;
 if not found or v_series.status<>'active'
   or v_series.starts_at is null or v_series.ends_at is null then
   raise exception 'Competition is not active';
 end if;
 select slot_id into v_slot from public.arena_series_members
  where series_id=v_series.id and user_id=v_actor and response='accepted';
 if v_slot is null then raise exception 'Not an accepted competitor'; end if;
 if p_started is null or p_ended is null
   or p_started < v_series.starts_at or p_ended > v_series.ends_at
   or p_started > now() or p_ended > now() + interval '2 minutes'
   or p_ended<=p_started
   or p_ended-p_started > interval '24 hours' then
   raise exception 'Workout must be completed inside the competition window';
 end if;
 v_wall_seconds := extract(epoch from p_ended-p_started);
 v_target := v_round.target_distance_meters;
 if v_target is null or v_target not between 100 and 500000
   or p_elapsed_seconds is null or p_elapsed_seconds < greatest(10,v_target/15)
   or p_elapsed_seconds > least(86400,greatest(1800,v_target*3.6))
   or p_elapsed_seconds > v_wall_seconds+120
   or p_distance_meters is null or p_distance_meters <= 0
   or abs(p_distance_meters-v_target) > v_target*0.05
   or p_distance_meters > v_wall_seconds*15
   or p_route_match_percent is null or p_route_match_percent < 90
   or p_route_match_percent > 100
   or p_start_gap_meters is null or p_start_gap_meters < 0 or p_start_gap_meters > 120
   or p_end_gap_meters is null or p_end_gap_meters < 0 or p_end_gap_meters > 120
 then
   raise exception 'Route report is not plausible for the agreed course';
 end if;
 -- No GPS track, heart rate, location timeline, or hidden HealthKit data is uploaded.
 -- Submitted values are NOT authenticated by the server; group approval remains mandatory.
 insert into public.arena_workout_evidence(
  series_id,round_id,slot_id,user_id,source_workout_id,source,
  activity_type,started_at,ended_at,metric_type,metric_value,
  reported_distance_meters,reported_route_match_percent,verification_level
 ) values (
  v_series.id,v_round.id,v_slot,v_actor,p_source_workout,'apple_health',
  'running',p_started,p_ended,'elapsed_seconds',p_elapsed_seconds,
  p_distance_meters,p_route_match_percent,'participant_reported'
 ) returning id into v_id;
 return v_id;
end;
$$;

revoke all on function public.arena_share_route_evidence(
 uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,numeric
) from public,anon;
grant execute on function public.arena_share_route_evidence(
 uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,numeric
) to authenticated;
