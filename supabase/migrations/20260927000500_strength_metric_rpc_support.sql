-- ATHLTH 1.4.1: allow native strength challenge metrics in v2 create/update APIs.

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
    'distance_km',
    'workouts',
    'active_minutes',
    'fastest_time_seconds',
    'strength_volume_kg',
    'heaviest_weight_kg',
    'strength_reps'
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

  select * into ch
  from public.community_group_challenges
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
    'distance_km',
    'workouts',
    'active_minutes',
    'fastest_time_seconds',
    'strength_volume_kg',
    'heaviest_weight_kg',
    'strength_reps'
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

create or replace function public.submit_community_group_manual_challenge_result(
  p_challenge_id uuid,
  p_contribution double precision,
  p_note text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  ch public.community_group_challenges%rowtype;
  result_id uuid := gen_random_uuid();
  attempt_count integer;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  select * into ch
  from public.community_group_challenges
  where id = p_challenge_id;

  if not found then
    raise exception 'Challenge not found';
  end if;

  if not private.is_community_group_member(ch.group_id, actor) then
    raise exception 'Group membership required';
  end if;

  if coalesce(ch.activity_config->>'activity_type','') <> 'strength'
     or ch.metric not in (
       'strength_volume_kg',
       'heaviest_weight_kg',
       'strength_reps'
     ) then
    raise exception 'Manual results are only available for strength metrics';
  end if;

  if ch.status = 'cancelled'
     or now() < ch.starts_at
     or now() > ch.ends_at then
    raise exception 'Challenge is not active';
  end if;

  if ch.join_required
     and not exists (
       select 1
       from public.community_group_challenge_participants p
       where p.challenge_id = ch.id
         and p.user_id = actor
         and p.status = 'joined'
     ) then
    raise exception 'Join the challenge before logging a result';
  end if;

  if p_contribution is null or p_contribution <= 0 then
    raise exception 'Result must be greater than zero';
  end if;

  if ch.attempt_limit is not null then
    select count(*) into attempt_count
    from public.community_group_challenge_workouts w
    where w.challenge_id = ch.id
      and w.user_id = actor;

    if attempt_count >= ch.attempt_limit then
      raise exception 'Attempt limit reached';
    end if;
  end if;

  insert into public.community_group_challenge_workouts(
    challenge_id,
    user_id,
    workout_id,
    contribution,
    route_match_percent,
    verification_status,
    is_manual,
    manual_note
  )
  values (
    ch.id,
    actor,
    result_id,
    p_contribution,
    null,
    'not_required',
    true,
    nullif(left(trim(coalesce(p_note,'')),500),'')
  );

  return result_id;
end;
$$;

grant execute on function public.create_community_group_challenge_v2(
  uuid,uuid,text,text,text,double precision,timestamptz,timestamptz,text,jsonb,jsonb
) to authenticated;
grant execute on function public.update_community_group_challenge_v2(
  uuid,text,text,text,double precision,timestamptz,timestamptz,jsonb,jsonb
) to authenticated;
grant execute on function public.submit_community_group_manual_challenge_result(
  uuid,double precision,text
) to authenticated;

revoke all on function public.create_community_group_challenge_v2(
  uuid,uuid,text,text,text,double precision,timestamptz,timestamptz,text,jsonb,jsonb
) from public, anon;
revoke all on function public.update_community_group_challenge_v2(
  uuid,text,text,text,double precision,timestamptz,timestamptz,jsonb,jsonb
) from public, anon;
revoke all on function public.submit_community_group_manual_challenge_result(
  uuid,double precision,text
) from public, anon;
