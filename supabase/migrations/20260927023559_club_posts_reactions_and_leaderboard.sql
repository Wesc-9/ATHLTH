create table if not exists public.community_group_announcement_reactions (
  announcement_id uuid not null references public.community_group_announcements(id) on delete cascade,
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null default 'like' check (reaction = 'like'),
  created_at timestamptz not null default now(),
  primary key (announcement_id, user_id, reaction)
);

create index if not exists community_group_announcement_reactions_group_idx
  on public.community_group_announcement_reactions(group_id, created_at desc);
create index if not exists community_group_announcement_reactions_user_idx
  on public.community_group_announcement_reactions(user_id, created_at desc);

alter table public.community_group_announcement_reactions enable row level security;

drop policy if exists group_announcement_reactions_select_members
  on public.community_group_announcement_reactions;
create policy group_announcement_reactions_select_members
  on public.community_group_announcement_reactions
  for select
  to authenticated
  using (
    private.is_community_group_member(group_id, (select auth.uid()))
    or exists (
      select 1
      from public.community_groups g
      where g.id = group_id
        and g.creator_id = (select auth.uid())
    )
  );

drop policy if exists group_announcement_reactions_insert_self
  on public.community_group_announcement_reactions;
create policy group_announcement_reactions_insert_self
  on public.community_group_announcement_reactions
  for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and (
      private.is_community_group_member(group_id, (select auth.uid()))
      or exists (
        select 1
        from public.community_groups g
        where g.id = group_id
          and g.creator_id = (select auth.uid())
      )
    )
    and exists (
      select 1
      from public.community_group_announcements a
      where a.id = announcement_id
        and a.group_id = group_id
    )
  );

drop policy if exists group_announcement_reactions_delete_self
  on public.community_group_announcement_reactions;
create policy group_announcement_reactions_delete_self
  on public.community_group_announcement_reactions
  for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    and (
      private.is_community_group_member(group_id, (select auth.uid()))
      or exists (
        select 1
        from public.community_groups g
        where g.id = group_id
          and g.creator_id = (select auth.uid())
      )
    )
  );

grant select, insert, delete
  on public.community_group_announcement_reactions
  to authenticated;

create table if not exists public.community_group_member_workouts (
  group_id uuid not null references public.community_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  workout_id uuid not null,
  completed_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id, workout_id)
);

create index if not exists community_group_member_workouts_group_time_idx
  on public.community_group_member_workouts(group_id, completed_at desc);
create index if not exists community_group_member_workouts_user_time_idx
  on public.community_group_member_workouts(user_id, completed_at desc);

alter table public.community_group_member_workouts enable row level security;
revoke all on public.community_group_member_workouts from anon, authenticated;

create or replace function public.record_community_group_workout(
  p_workout_id uuid,
  p_completed_at timestamptz
)
returns void
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

  insert into public.community_group_member_workouts(
    group_id,
    user_id,
    workout_id,
    completed_at
  )
  select member_groups.group_id, actor, p_workout_id, p_completed_at
  from (
    select gm.group_id
    from public.community_group_members gm
    where gm.user_id = actor
    union
    select g.id
    from public.community_groups g
    where g.creator_id = actor
  ) as member_groups
  on conflict (group_id, user_id, workout_id)
  do update set completed_at = excluded.completed_at;
end;
$$;

revoke all on function public.record_community_group_workout(uuid,timestamptz)
  from public, anon;
grant execute on function public.record_community_group_workout(uuid,timestamptz)
  to authenticated;

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
  ),
  workouts as (
    select w.user_id, count(distinct w.workout_id)::bigint as raw_count
    from workout_events w
    group by w.user_id
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
    select user_id, sum(capped_count)::bigint as points
    from messages_daily
    group by user_id
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
    select user_id, sum(capped_count)::bigint as points
    from likes_daily
    group by user_id
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
    select p.user_id, count(distinct p.challenge_id)::bigint as raw_count
    from public.community_group_challenge_participants p
    join public.community_group_challenges c
      on c.id = p.challenge_id
    where p.group_id = p_group_id
      and p.status = 'joined'
      and p.joined_at >= since_at
      and c.status <> 'cancelled'
    group by p.user_id
  )
  select
    mi.user_id,
    coalesce(w.raw_count, 0)::bigint as workout_count,
    coalesce(mr.raw_count, 0)::bigint as message_count,
    coalesce(lr.raw_count, 0)::bigint as likes_given,
    coalesce(ec.raw_count, 0)::bigint as events_joined,
    coalesce(cc.raw_count, 0)::bigint as challenges_joined,
    (
      coalesce(w.raw_count, 0) * 5
      + coalesce(mp.points, 0)
      + coalesce(lp.points, 0)
      + coalesce(ec.raw_count, 0) * 5
      + coalesce(cc.raw_count, 0) * 5
    )::bigint as score
  from member_ids mi
  left join workouts w on w.user_id = mi.user_id
  left join messages_raw mr on mr.user_id = mi.user_id
  left join message_points mp on mp.user_id = mi.user_id
  left join likes_raw lr on lr.user_id = mi.user_id
  left join like_points lp on lp.user_id = mi.user_id
  left join event_counts ec on ec.user_id = mi.user_id
  left join challenge_counts cc on cc.user_id = mi.user_id
  order by score desc, workout_count desc, message_count desc, mi.user_id;
end;
$$;

revoke all on function public.get_community_group_leaderboard(uuid)
  from public, anon;
grant execute on function public.get_community_group_leaderboard(uuid)
  to authenticated;
