-- ATHLTH 1.4.1 advanced create APIs and verified group attempts.

alter table public.community_group_challenge_workouts
  add column if not exists route_match_percent double precision,
  add column if not exists verification_status text not null default 'not_required';

alter table public.community_group_challenge_workouts
  drop constraint if exists community_group_challenge_workouts_verification_check,
  drop constraint if exists community_group_challenge_workouts_route_match_check;

alter table public.community_group_challenge_workouts
  add constraint community_group_challenge_workouts_verification_check
    check (verification_status in ('not_required','verified','unverified')),
  add constraint community_group_challenge_workouts_route_match_check
    check (
      route_match_percent is null
      or route_match_percent between 0 and 100
    );

create or replace function public.create_community_group_event_v2(
  p_id uuid,
  p_group_id uuid,
  p_title text,
  p_summary text,
  p_activity_type text,
  p_starts_at timestamptz,
  p_meeting_name text,
  p_image_url text,
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
  v_organizer_kind text := coalesce(p_options->>'organizer_kind', 'person');
  v_status text := coalesce(p_options->>'status', 'upcoming');
  v_capacity integer;
  v_rsvp_deadline timestamptz;
  v_ends_at timestamptz;
  v_meeting_lat double precision;
  v_meeting_long double precision;
  v_repeat_rule text;
  v_repeat_until timestamptz;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if not private.can_create_community_group_content(p_group_id, actor) then
    raise exception 'You do not have permission to create group events';
  end if;

  if char_length(trim(coalesce(p_title, ''))) not between 1 and 160 then
    raise exception 'Event title is required';
  end if;

  if v_organizer_kind not in ('person','group') then
    raise exception 'Invalid organizer';
  end if;

  if v_status not in ('draft','upcoming') then
    raise exception 'Invalid event status';
  end if;

  v_capacity := nullif(p_options->>'capacity','')::integer;
  v_rsvp_deadline := nullif(p_options->>'rsvp_deadline','')::timestamptz;
  v_ends_at := nullif(p_options->>'ends_at','')::timestamptz;
  v_meeting_lat := nullif(p_options->>'meeting_lat','')::double precision;
  v_meeting_long := nullif(p_options->>'meeting_long','')::double precision;
  v_repeat_rule := nullif(p_options->>'repeat_rule','');
  v_repeat_until := nullif(p_options->>'repeat_until','')::timestamptz;

  if v_capacity is not null and v_capacity <= 0 then
    raise exception 'Capacity must be greater than zero';
  end if;

  if v_rsvp_deadline is not null and v_rsvp_deadline > p_starts_at then
    raise exception 'RSVP deadline must be before the event starts';
  end if;

  if v_ends_at is not null and v_ends_at <= p_starts_at then
    raise exception 'Event end must be after the start';
  end if;

  if v_repeat_rule is not null and v_repeat_rule <> 'weekly' then
    raise exception 'Invalid repeat rule';
  end if;

  insert into public.community_group_events(
    id, group_id, creator_id, title, summary, activity_type,
    starts_at, ends_at, meeting_name, image_url, activity_config,
    status, organizer_kind, organizer_user_id, capacity,
    rsvp_deadline, meeting_lat, meeting_long, repeat_rule,
    repeat_until, series_id
  )
  values (
    p_id, p_group_id, actor, trim(p_title),
    left(coalesce(p_summary,''),1200),
    coalesce(nullif(trim(p_activity_type),''),'other'),
    p_starts_at, v_ends_at, left(coalesce(p_meeting_name,''),180),
    nullif(p_image_url,''), p_activity_config,
    v_status, v_organizer_kind,
    case when v_organizer_kind='person' then actor else null end,
    v_capacity, v_rsvp_deadline, v_meeting_lat, v_meeting_long,
    v_repeat_rule, v_repeat_until,
    case when v_repeat_rule is not null then p_id else null end
  );

  return p_id;
end;
$$;

create or replace function public.create_community_group_challenge_v2(
  p_id uuid,
  p_group_id uuid,
  p_title text,
  p_summary text,
  p_metric text,
  p_target_value double precision,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_image_url text,
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
  v_organizer_kind text := coalesce(p_options->>'organizer_kind','person');
  v_status text := coalesce(p_options->>'status','upcoming');
  v_scoring_mode text := coalesce(p_options->>'scoring_mode','cumulative');
  v_attempt_limit integer;
  v_route_verify boolean := coalesce((p_options->>'route_verification_enabled')::boolean,false);
  v_route_tolerance integer := coalesce((p_options->>'route_tolerance_meters')::integer,100);
  v_join_required boolean := coalesce((p_options->>'join_required')::boolean,true);
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if not private.can_create_community_group_content(p_group_id, actor) then
    raise exception 'You do not have permission to create group challenges';
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

  if v_organizer_kind not in ('person','group') then
    raise exception 'Invalid organizer';
  end if;

  if v_status not in ('draft','upcoming') then
    raise exception 'Invalid challenge status';
  end if;

  if v_scoring_mode not in ('cumulative','best_attempt','complete_target') then
    raise exception 'Invalid scoring mode';
  end if;

  v_attempt_limit := nullif(p_options->>'attempt_limit','')::integer;

  if v_attempt_limit is not null and v_attempt_limit <= 0 then
    raise exception 'Attempt limit must be greater than zero';
  end if;

  if v_route_tolerance not between 25 and 1000 then
    raise exception 'Route tolerance must be between 25 and 1000 metres';
  end if;

  insert into public.community_group_challenges(
    id, group_id, creator_id, title, summary, metric, target_value,
    starts_at, ends_at, image_url, activity_config,
    status, organizer_kind, organizer_user_id, scoring_mode,
    attempt_limit, route_verification_enabled, route_tolerance_meters,
    join_required
  )
  values (
    p_id, p_group_id, actor, trim(p_title),
    left(coalesce(p_summary,''),800),
    p_metric, p_target_value, p_starts_at, p_ends_at,
    nullif(p_image_url,''), p_activity_config,
    v_status, v_organizer_kind,
    case when v_organizer_kind='person' then actor else null end,
    v_scoring_mode, v_attempt_limit, v_route_verify,
    v_route_tolerance, v_join_required
  );

  if v_join_required then
    insert into public.community_group_challenge_participants(
      group_id, challenge_id, user_id, status
    )
    values (p_group_id, p_id, actor, 'joined')
    on conflict (challenge_id,user_id)
    do update set status='joined';
  end if;

  return p_id;
end;
$$;

grant execute on function public.create_community_group_event_v2(
  uuid,uuid,text,text,text,timestamptz,text,text,jsonb,jsonb
) to authenticated;
revoke all on function public.create_community_group_event_v2(
  uuid,uuid,text,text,text,timestamptz,text,text,jsonb,jsonb
) from public, anon;

grant execute on function public.create_community_group_challenge_v2(
  uuid,uuid,text,text,text,double precision,timestamptz,timestamptz,text,jsonb,jsonb
) to authenticated;
revoke all on function public.create_community_group_challenge_v2(
  uuid,uuid,text,text,text,double precision,timestamptz,timestamptz,text,jsonb,jsonb
) from public, anon;
