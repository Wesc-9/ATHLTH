-- Arena 2.0: structured custom-distance and shared route rounds.
-- Historical rounds keep their type and nullable metadata. Route time trials
-- remain explicitly participant-reviewed, NOT automatically GPS-verified.
alter table public.arena_round_proposals
  add column if not exists target_distance_meters numeric(10,2),
  add column if not exists route_snapshot jsonb;

alter table public.arena_round_proposals
  drop constraint if exists arena_round_proposals_template_check;
alter table public.arena_round_proposals
  add constraint arena_round_proposals_template_check
  check (template in (
    'fastest5K','fastest1K','fastestDistance','fastestRoute',
    'mostDistance','mostWorkouts','mostRepetitions','custom'
  ));

alter table public.arena_round_proposals
  add constraint arena_round_target_configuration_check
  check (
    (template = 'fastestDistance'
      and target_distance_meters between 100 and 500000
      and route_snapshot is null)
    or (template = 'fastestRoute'
      and target_distance_meters between 100 and 500000
      and route_snapshot is not null
      and jsonb_typeof(route_snapshot) = 'object')
    or (template not in ('fastestDistance','fastestRoute')
      and target_distance_meters is null
      and route_snapshot is null)
  );

comment on column public.arena_round_proposals.route_snapshot is
  'Route preview deliberately shared with the selected Arena participants. No GPS proof or location tracking is implied.';

-- Keep existing RPC signatures and RLS behavior so previously published
-- clients continue to work; publish the new optional columns atomically.

create or replace function public.arena_publish_series(
  p_title text,
  p_scope text,
  p_scoring text,
  p_duration_days int,
  p_invitees uuid[],
  p_rounds jsonb
) returns uuid
language plpgsql security invoker
set search_path = pg_catalog, public, private
as $$
declare
  v_id uuid;
  v_actor uuid := (select auth.uid());
  v_rec jsonb;
  v_friend uuid;
  v_order integer := 0;
begin
  if v_actor is null then raise exception 'Sign in required'; end if;
  if p_scope not in ('duel','friends') then
    raise exception 'Club series require a verified Club membership workflow';
  end if;
  if coalesce(cardinality(p_invitees),0) < 1 or cardinality(p_invitees) > 20 then
    raise exception 'Invite between 1 and 20 participants';
  end if;
  if p_scope = 'duel' and cardinality(p_invitees) <> 1 then
    raise exception 'A duel requires exactly one opponent';
  end if;
  if (select count(distinct x) from unnest(p_invitees) x) <> cardinality(p_invitees)
     or v_actor = any(p_invitees) then
    raise exception 'Invitees must be distinct from the organizer';
  end if;
  if jsonb_typeof(p_rounds) is distinct from 'array'
     or jsonb_array_length(p_rounds) not between 1 and 16 then
    raise exception 'A series requires between 1 and 16 rounds';
  end if;

  insert into public.arena_series(owner_id,title,scope,scoring,duration_days)
  values(v_actor,p_title,p_scope,p_scoring,p_duration_days)
  returning id into v_id;

  foreach v_friend in array p_invitees loop
    insert into public.arena_series_members(series_id,user_id,response)
    values(v_id,v_friend,'invited');
  end loop;

  for v_rec in select value from jsonb_array_elements(p_rounds) loop
    insert into public.arena_round_proposals(
      series_id,proposed_by,template,title,rules,position,\n      target_distance_meters,route_snapshot
    ) values (
      v_id,v_actor,v_rec->>'template',v_rec->>'title',
      v_rec->>'rules',v_order,\n      (v_rec->>'target_distance_meters')::numeric,v_rec->'route_snapshot'
    );
    v_order := v_order + 1;
  end loop;
  return v_id;
end;
$$;

create or replace function public.arena_publish_club_series(
 p_club uuid, p_title text, p_scoring text, p_duration_days integer,
 p_invitees uuid[], p_rounds jsonb
) returns uuid language plpgsql security invoker
set search_path=pg_catalog,public,private
as $$
declare
 v_actor uuid := (select auth.uid());
 v_series uuid;
 v_user uuid;
 v_round jsonb;
 v_position integer := 0;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 if p_club is null or not private.can_manage_community_group(p_club) then
   raise exception 'Only Club admins may publish Club Arena competitions';
 end if;
 if p_title is null or length(btrim(p_title)) not between 1 and 80
   or p_scoring not in ('winner','podium')
   or p_duration_days not between 1 and 90 then
   raise exception 'Invalid Club competition settings';
 end if;
 if p_invitees is null or cardinality(p_invitees) not between 1 and 20
   or v_actor=any(p_invitees)
   or (select count(distinct x) from unnest(p_invitees) x) <> cardinality(p_invitees) then
   raise exception 'Select 1 to 20 unique Club athletes other than yourself';
 end if;
 if jsonb_typeof(p_rounds) is distinct from 'array'
   or jsonb_array_length(p_rounds) not between 1 and 16 then
   raise exception 'Select 1 to 16 rounds';
 end if;
 foreach v_user in array p_invitees loop
   if not exists (
     select 1 from public.community_group_members gm
     where gm.group_id=p_club and gm.user_id=v_user
   ) then raise exception 'Invitee is not a Club member'; end if;
   if not private.arena_can_invite(v_user) then
     raise exception 'An invitee does not allow Arena invitations';
   end if;
 end loop;
 insert into public.arena_series(owner_id,title,scope,scoring,duration_days,club_id)
 values(v_actor,btrim(p_title),'club',p_scoring,p_duration_days,p_club)
 returning id into v_series;
 foreach v_user in array p_invitees loop
   insert into public.arena_series_members(series_id,user_id,response)
   values(v_series,v_user,'invited');
 end loop;
 for v_round in select value from jsonb_array_elements(p_rounds) loop
   insert into public.arena_round_proposals(
    series_id,proposed_by,template,title,rules,position,\n      target_distance_meters,route_snapshot
   ) values(
    v_series,v_actor,v_round->>'template',v_round->>'title',
    v_round->>'rules',v_position,\n    (v_round->>'target_distance_meters')::numeric,v_round->'route_snapshot'
   );
   v_position := v_position+1;
 end loop;
 return v_series;
end;
$$;

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
   or (p_distance is not null and (p_distance<=0 or p_distance>500000))
   or (p_source='iphone' and p_activity='strength')
   or (p_source='athlth_strength' and p_activity<>'strength') then
   raise exception 'Invalid workout evidence fields';
 end if;
 if v_round.template in ('fastest5K','fastest1K','fastestDistance') then
   if v_round.template='fastest5K' then
     v_target := 5000;
     v_min_seconds := 600;
     v_max_seconds := 18000;
   elsif v_round.template='fastest1K' then
     v_target := 1000;
     v_min_seconds := 100;
     v_max_seconds := 7200;
   else
     v_target := v_round.target_distance_meters;
     if v_target is null or v_target<100 or v_target>500000 then
       raise exception 'Custom distance must be between 100 and 500000 meters';
     end if;
     v_min_seconds := greatest(10, v_target/15);
     v_max_seconds := least(86400, greatest(1800, v_target*3.6));
   end if;
   if p_activity<>'running' or p_metric_type<>'elapsed_seconds'
     or p_distance is null or abs(p_distance-v_target)>v_target*0.02
     or p_metric < v_min_seconds
     or p_metric > v_max_seconds
     or p_metric > v_wall_seconds+120
     or p_metric < v_min_seconds then
     raise exception 'Timed run must have matching full-workout distance and elapsed time';
   end if;
 elsif v_round.template='mostDistance' then
   if p_activity not in ('running','walking') or p_metric_type<>'distance_meters'
     or p_distance is null or abs(p_distance-p_metric)>1
     or p_metric<300 or v_wall_seconds<300
     or p_metric>v_wall_seconds*15 then
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
end;\n$$;
