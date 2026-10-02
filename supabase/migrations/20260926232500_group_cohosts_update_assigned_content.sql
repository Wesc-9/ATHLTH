drop policy if exists group_events_update_allowed
on public.community_group_events;

create policy group_events_update_allowed
on public.community_group_events
for update
to authenticated
using (
  private.can_manage_community_group_content(
    group_id,
    'event',
    id,
    (select auth.uid())
  )
)
with check (
  private.can_manage_community_group_content(
    group_id,
    'event',
    id,
    (select auth.uid())
  )
);

drop policy if exists group_challenges_update_allowed
on public.community_group_challenges;

create policy group_challenges_update_allowed
on public.community_group_challenges
for update
to authenticated
using (
  private.can_manage_community_group_content(
    group_id,
    'challenge',
    id,
    (select auth.uid())
  )
)
with check (
  private.can_manage_community_group_content(
    group_id,
    'challenge',
    id,
    (select auth.uid())
  )
);
