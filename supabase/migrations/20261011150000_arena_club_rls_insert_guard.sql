-- Prevent bypassing the Club manager and membership checks by directly
-- inserting into public Arena tables instead of calling the Club RPC.
-- Keep the original duel/friends behavior unchanged.
drop policy if exists arena_series_insert on public.arena_series;
create policy arena_series_insert on public.arena_series
for insert to authenticated
with check (
  owner_id = (select auth.uid())
  and status = 'draft'
  and (
    scope <> 'club'
    or (
      club_id is not null
      and private.can_manage_community_group(club_id)
    )
  )
);

drop policy if exists arena_members_invite on public.arena_series_members;
create policy arena_members_invite on public.arena_series_members
for insert to authenticated
with check (
  response = 'invited'
  and private.arena_can_invite(user_id)
  and exists (
    select 1 from public.arena_series s
    where s.id = series_id
      and s.owner_id = (select auth.uid())
      and s.status = 'draft'
      and (
        s.scope <> 'club'
        or exists (
          select 1 from public.community_group_members gm
          where gm.group_id = s.club_id
            and gm.user_id = arena_series_members.user_id
        )
      )
  )
);