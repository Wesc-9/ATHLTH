-- ATHLTH 1.4.1 strength metrics and explicit manual strength results.

alter table public.community_group_challenges
  drop constraint if exists community_group_challenges_metric_check;

alter table public.community_group_challenges
  add constraint community_group_challenges_metric_check
  check (
    metric in (
      'distance_km',
      'workouts',
      'active_minutes',
      'fastest_time_seconds',
      'strength_volume_kg',
      'heaviest_weight_kg',
      'strength_reps'
    )
  );

alter table public.community_group_challenge_workouts
  add column if not exists is_manual boolean not null default false,
  add column if not exists manual_note text;

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

  if not private.is_community_group_member(
    ch.group_id,
    actor
  ) then
    raise exception 'Group membership required';
  end if;

  if coalesce(
    ch.activity_config->>'activity_type',
    ''
  ) <> 'strength' then
    raise exception 'Manual results are only available for strength challenges';
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

  if p_contribution is null
     or p_contribution <= 0 then
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

grant execute on function public.submit_community_group_manual_challenge_result(
  uuid,double precision,text
) to authenticated;
revoke all on function public.submit_community_group_manual_challenge_result(
  uuid,double precision,text
) from public, anon;
