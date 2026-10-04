-- ATHLTH 1.4.1 update APIs for advanced group events/challenges.

create or replace function public.update_community_group_event_v2(
  p_event_id uuid,
  p_title text,
  p_summary text,
  p_activity_type text,
  p_starts_at timestamptz,
  p_meeting_name text,
  p_activity_config jsonb,
  p_options jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  ev public.community_group_events%rowtype;
  v_organizer_kind text := coalesce(p_options->>'organizer_kind','person');
  v_status text := coalesce(p_options->>'status','upcoming');
  v_capacity integer := nullif(p_options->>'capacity','')::integer;
  v_rsvp_deadline timestamptz := nullif(p_options->>'rsvp_deadline','')::timestamptz;
  v_ends_at timestamptz := nullif(p_options->>'ends_at','')::timestamptz;
  v_meeting_lat double precision := nullif(p_options->>'meeting_lat','')::double precision;
  v_meeting_long double precision := nullif(p_options->>'meeting_long','')::double precision;
  v_repeat_rule text := nullif(p_options->>'repeat_rule','');
  v_repeat_until timestamptz := nullif(p_options->>'repeat_until','')::timestamptz;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select * into ev from public.community_group_events
  where id = p_event_id;

  if not found then
    raise exception 'Event not found';
  end if;

  if not private.can_manage_community_group_content(
    ev.group_id, 'event', ev.id, actor
  ) then
    raise exception 'Event management permission required';
  end if;

  if char_length(trim(coalesce(p_title,''))) not between 1 and 160 then
    raise exception 'Event title is required';
  end if;

  if v_organizer_kind not in ('person','group') then
    raise exception 'Invalid organizer';
  end if;

  if v_status not in ('draft','upcoming','cancelled') then
    raise exception 'Invalid event status';
  end if;

  if v_capacity is not null and v_capacity <= 0 then
    raise exception 'Capacity must be greater than zero';
  end if;

  if v_rsvp_deadline is not null and v_rsvp_deadline > p_starts_at then
    raise exception 'RSVP deadline must be before event start';
  end if;

  if v_ends_at is not null and v_ends_at <= p_starts_at then
    raise exception 'Event end must be after start';
  end if;

  update public.community_group_events
  set
    title = trim(p_title),
    summary = left(coalesce(p_summary,''),1200),
    activity_type = coalesce(nullif(trim(p_activity_type),''),'other'),
    starts_at = p_starts_at,
    ends_at = v_ends_at,
    meeting_name = left(coalesce(p_meeting_name,''),180),
    activity_config = p_activity_config,
    status = v_status,
    organizer_kind = v_organizer_kind,
    organizer_user_id = case when v_organizer_kind='person' then actor else null end,
    capacity = v_capacity,
    rsvp_deadline = v_rsvp_deadline,
    meeting_lat = v_meeting_lat,
    meeting_long = v_meeting_long,
    repeat_rule = v_repeat_rule,
    repeat_until = v_repeat_until,
    updated_at = now()
  where id = p_event_id;

  return p_event_id;
end;
$$;

create or replace function public.update_community_group_challenge_v2(
  p_challenge_id uuid,
  p_title text,
  p_summary text,
  p_metric text,
  p_target_value double precision,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_activity_config jsonb,
  p_options jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  ch public.community_group_challenges%rowtype;
  v_organizer_kind text := coalesce(p_options->>'organizer_kind','person');
  v_status text := coalesce(p_options->>'status','upcoming');
  v_scoring_mode text := coalesce(p_options->>'scoring_mode','cumulative');
  v_attempt_limit integer := nullif(p_options->>'attempt_limit','')::integer;
  v_route_verify boolean := coalesce((p_options->>'route_verification_enabled')::boolean,false);
  v_route_tolerance integer := coalesce((p_options->>'route_tolerance_meters')::integer,100);
  v_join_required boolean := coalesce((p_options->>'join_required')::boolean,true);
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select * into ch from public.community_group_challenges
  where id = p_challenge_id;

  if not found then
    raise exception 'Challenge not found';
  end if;

  if not private.can_manage_community_group_content(
    ch.group_id, 'challenge', ch.id, actor
  ) then
    raise exception 'Challenge management permission required';
  end if;

  if char_length(trim(coalesce(p_title,''))) not between 1 and 160 then
    raise exception 'Challenge title is required';
  end if;

  if p_metric not in (
    'distance_km','workouts','active_minutes','fastest_time_seconds'
  ) then
    raise exception 'Invalid challenge metric';
  end if;

  if p_target_value is null or p_target_value <= 0 then
    raise exception 'Challenge target must be greater than zero';
  end if;

  if p_ends_at <= p_starts_at then
    raise exception 'Challenge must end after it starts';
  end if;

  if v_status not in ('draft','upcoming','cancelled') then
    raise exception 'Invalid challenge status';
  end if;

  update public.community_group_challenges
  set
    title = trim(p_title),
    summary = left(coalesce(p_summary,''),800),
    metric = p_metric,
    target_value = p_target_value,
    starts_at = p_starts_at,
    ends_at = p_ends_at,
    activity_config = p_activity_config,
    status = v_status,
    organizer_kind = v_organizer_kind,
    organizer_user_id = case when v_organizer_kind='person' then actor else null end,
    scoring_mode = v_scoring_mode,
    attempt_limit = v_attempt_limit,
    route_verification_enabled = v_route_verify,
    route_tolerance_meters = v_route_tolerance,
    join_required = v_join_required,
    updated_at = now()
  where id = p_challenge_id;

  return p_challenge_id;
end;
$$;

grant execute on function public.update_community_group_event_v2(
  uuid,text,text,text,timestamptz,text,jsonb,jsonb
) to authenticated;
revoke all on function public.update_community_group_event_v2(
  uuid,text,text,text,timestamptz,text,jsonb,jsonb
) from public, anon;

grant execute on function public.update_community_group_challenge_v2(
  uuid,text,text,text,double precision,timestamptz,timestamptz,jsonb,jsonb
) to authenticated;
revoke all on function public.update_community_group_challenge_v2(
  uuid,text,text,text,double precision,timestamptz,timestamptz,jsonb,jsonb
) from public, anon;
