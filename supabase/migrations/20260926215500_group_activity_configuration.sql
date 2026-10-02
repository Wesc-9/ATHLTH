-- ATHLTH 1.4.1 group activity configuration + reliable creation RPCs.

alter table public.community_group_events
  add column if not exists activity_config jsonb;

alter table public.community_group_challenges
  add column if not exists activity_config jsonb;

create or replace function public.create_community_group_event(
  p_id uuid,
  p_group_id uuid,
  p_title text,
  p_summary text,
  p_activity_type text,
  p_starts_at timestamptz,
  p_meeting_name text,
  p_image_url text,
  p_activity_config jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if not private.can_create_community_group_content(
    p_group_id,
    actor
  ) then
    raise exception 'You do not have permission to create group events';
  end if;

  if char_length(trim(coalesce(p_title, ''))) not between 1 and 160 then
    raise exception 'Event title is required';
  end if;

  if p_activity_config is not null
     and jsonb_typeof(p_activity_config) <> 'object' then
    raise exception 'Invalid activity configuration';
  end if;

  insert into public.community_group_events(
    id,
    group_id,
    creator_id,
    title,
    summary,
    activity_type,
    starts_at,
    ends_at,
    meeting_name,
    image_url,
    activity_config
  )
  values (
    p_id,
    p_group_id,
    actor,
    trim(p_title),
    left(coalesce(p_summary, ''), 1200),
    coalesce(nullif(trim(p_activity_type), ''), 'other'),
    p_starts_at,
    null,
    left(coalesce(p_meeting_name, ''), 180),
    nullif(p_image_url, ''),
    p_activity_config
  );

  return p_id;
end;
$$;

create or replace function public.create_community_group_challenge(
  p_id uuid,
  p_group_id uuid,
  p_title text,
  p_summary text,
  p_metric text,
  p_target_value double precision,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_image_url text,
  p_activity_config jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if not private.can_create_community_group_content(
    p_group_id,
    actor
  ) then
    raise exception 'You do not have permission to create group challenges';
  end if;

  if char_length(trim(coalesce(p_title, ''))) not between 1 and 160 then
    raise exception 'Challenge title is required';
  end if;

  if p_metric not in ('distance_km', 'workouts', 'active_minutes') then
    raise exception 'Invalid challenge metric';
  end if;

  if p_target_value is null or p_target_value <= 0 then
    raise exception 'Challenge target must be greater than zero';
  end if;

  if p_ends_at <= p_starts_at then
    raise exception 'Challenge must end after it starts';
  end if;

  if p_activity_config is not null
     and jsonb_typeof(p_activity_config) <> 'object' then
    raise exception 'Invalid activity configuration';
  end if;

  insert into public.community_group_challenges(
    id,
    group_id,
    creator_id,
    title,
    summary,
    metric,
    target_value,
    starts_at,
    ends_at,
    image_url,
    activity_config
  )
  values (
    p_id,
    p_group_id,
    actor,
    trim(p_title),
    left(coalesce(p_summary, ''), 800),
    p_metric,
    p_target_value,
    p_starts_at,
    p_ends_at,
    nullif(p_image_url, ''),
    p_activity_config
  );

  return p_id;
end;
$$;

revoke all on function public.create_community_group_event(
  uuid, uuid, text, text, text, timestamptz, text, text, jsonb
) from public, anon;
grant execute on function public.create_community_group_event(
  uuid, uuid, text, text, text, timestamptz, text, text, jsonb
) to authenticated;

revoke all on function public.create_community_group_challenge(
  uuid, uuid, text, text, text, double precision, timestamptz, timestamptz, text, jsonb
) from public, anon;
grant execute on function public.create_community_group_challenge(
  uuid, uuid, text, text, text, double precision, timestamptz, timestamptz, text, jsonb
) to authenticated;
