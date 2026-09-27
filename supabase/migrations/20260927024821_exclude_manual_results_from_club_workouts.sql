create or replace function public.get_community_group_leaderboard(
  p_group_id uuid
)
returns table (
  user_id uuid,
  workout_count bigint,
  message_count bigint,
  likes_given bigint,
  events_joined bigint,
  challenges_joined bigint,
  score bigint
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  since_at timestamptz := now() - interval '7 days';
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  if not (
    private.is_community_group_member(p_group_id, actor)
    or exists (
      select 1
      from public.community_groups g
      where g.id = p_group_id
        and g.creator_id = actor
    )
  ) then
    raise exception 'Group membership required';
  end if;

  return query
  with member_ids as (
    select gm.user_id
    from public.community_group_members gm
    where gm.group_id = p_group_id
    union
    select g.creator_id
    from public.community_groups g
    where g.id = p_group_id
  ),
  workout_events as (
    select w.user_id, w.workout_id, w.completed_at
    from public.community_group_member_workouts w
    where w.group_id = p_group_id
      and w.completed_at >= since_at

    union

    select cw.user_id, cw.workout_id, cw.created_at
    from public.community_group_challenge_workouts cw
    join public.community_group_challenges c
      on c.id = cw.challenge_id
    where c.group_id = p_group_id
      and cw.created_at >= since_at
      and cw.verification_status <> 'unverified'
      and coalesce(cw.is_manual, false) = false
  ),
  workouts as (
    select we.user_id, count(distinct we.workout_id)::bigint as raw_count
    from workout_events we
    group by we.user_id
  ),
  messages_raw as (
    select m.sender_id as user_id, count(*)::bigint as raw_count
    from public.community_group_messages m
    where m.group_id = p_group_id
      and m.created_at >= since_at
    group by m.sender_id
  ),
  messages_daily as (
    select
      m.sender_id as user_id,
      (m.created_at at time zone 'UTC')::date as activity_day,
      least(count(*), 5)::bigint as capped_count
    from public.community_group_messages m
    where m.group_id = p_group_id
      and m.created_at >= since_at
    group by m.sender_id, (m.created_at at time zone 'UTC')::date
  ),
  message_points as (
    select md.user_id, sum(md.capped_count)::bigint as points
    from messages_daily md
    group by md.user_id
  ),
  likes_raw as (
    select r.user_id, count(*)::bigint as raw_count
    from public.community_group_announcement_reactions r
    join public.community_group_announcements a
      on a.id = r.announcement_id
    where r.group_id = p_group_id
      and r.created_at >= since_at
      and r.reaction = 'like'
      and a.author_id <> r.user_id
    group by r.user_id
  ),
  likes_daily as (
    select
      r.user_id,
      (r.created_at at time zone 'UTC')::date as activity_day,
      least(count(*), 5)::bigint as capped_count
    from public.community_group_announcement_reactions r
    join public.community_group_announcements a
      on a.id = r.announcement_id
    where r.group_id = p_group_id
      and r.created_at >= since_at
      and r.reaction = 'like'
      and a.author_id <> r.user_id
    group by r.user_id, (r.created_at at time zone 'UTC')::date
  ),
  like_points as (
    select ld.user_id, sum(ld.capped_count)::bigint as points
    from likes_daily ld
    group by ld.user_id
  ),
  event_counts as (
    select r.user_id, count(distinct r.event_id)::bigint as raw_count
    from public.community_group_event_rsvps r
    join public.community_group_events e
      on e.id = r.event_id
    where r.group_id = p_group_id
      and r.status = 'going'
      and e.starts_at >= since_at
      and e.starts_at <= now()
      and e.status <> 'cancelled'
    group by r.user_id
  ),
  challenge_counts as (
    select cp.user_id, count(distinct cp.challenge_id)::bigint as raw_count
    from public.community_group_challenge_participants cp
    join public.community_group_challenges c
      on c.id = cp.challenge_id
    where cp.group_id = p_group_id
      and cp.status = 'joined'
      and cp.joined_at >= since_at
      and c.status <> 'cancelled'
    group by cp.user_id
  )
  select
    mi.user_id,
    coalesce(w.raw_count, 0)::bigint,
    coalesce(mr.raw_count, 0)::bigint,
    coalesce(lr.raw_count, 0)::bigint,
    coalesce(ec.raw_count, 0)::bigint,
    coalesce(cc.raw_count, 0)::bigint,
    (
      coalesce(w.raw_count, 0) * 5
      + coalesce(mp.points, 0)
      + coalesce(lp.points, 0)
      + coalesce(ec.raw_count, 0) * 5
      + coalesce(cc.raw_count, 0) * 5
    )::bigint
  from member_ids mi
  left join workouts w on w.user_id = mi.user_id
  left join messages_raw mr on mr.user_id = mi.user_id
  left join message_points mp on mp.user_id = mi.user_id
  left join likes_raw lr on lr.user_id = mi.user_id
  left join like_points lp on lp.user_id = mi.user_id
  left join event_counts ec on ec.user_id = mi.user_id
  left join challenge_counts cc on cc.user_id = mi.user_id
  order by 7 desc, 2 desc, 3 desc, mi.user_id;
end;
$$;

revoke all on function public.get_community_group_leaderboard(uuid)
  from public, anon;
grant execute on function public.get_community_group_leaderboard(uuid)
  to authenticated;
