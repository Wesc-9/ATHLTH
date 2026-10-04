drop policy if exists group_events_select_members
on public.community_group_events;

create policy group_events_select_members
on public.community_group_events
for select
to authenticated
using (
  private.is_community_group_member(
    group_id,
    (select auth.uid())
  )
  and (
    status <> 'draft'
    or private.can_manage_community_group_content(
      group_id,
      'event',
      id,
      (select auth.uid())
    )
  )
);

drop policy if exists group_challenges_select_members
on public.community_group_challenges;

create policy group_challenges_select_members
on public.community_group_challenges
for select
to authenticated
using (
  private.is_community_group_member(
    group_id,
    (select auth.uid())
  )
  and (
    status <> 'draft'
    or private.can_manage_community_group_content(
      group_id,
      'challenge',
      id,
      (select auth.uid())
    )
  )
);
