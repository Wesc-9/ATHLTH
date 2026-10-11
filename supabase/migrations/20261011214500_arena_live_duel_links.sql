-- Explicit, permission-checked link from a Live Ghost invitation to an
-- active 1v1 Arena round. This is evidence provenance, NOT automatic points.
alter table public.ghost_race_challenges
  add column if not exists arena_round_id uuid
  references public.arena_round_proposals(id) on delete set null;

create index if not exists ghost_race_arena_round_idx
  on public.ghost_race_challenges(arena_round_id,created_at desc)
  where arena_round_id is not null;

create or replace function private.ghost_race_arena_link_allowed(
  p_round_id uuid, p_sender uuid, p_recipient uuid
) returns boolean
language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from public.arena_round_proposals r
    join public.arena_series s on s.id = r.series_id
    where r.id = p_round_id
      and s.scope = 'duel'
      and s.status = 'active'
      and r.template in ('fastest5K','fastest1K','fastestDistance','fastestRoute')
      and exists (
        select 1 from public.arena_series_members m
        where m.series_id = s.id and m.user_id = p_sender
          and m.response = 'accepted'
      )
      and exists (
        select 1 from public.arena_series_members m
        where m.series_id = s.id and m.user_id = p_recipient
          and m.response = 'accepted'
      )
      and (
        select count(*) from public.arena_series_members m
        where m.series_id = s.id and m.response = 'accepted'
          and m.user_id is not null
      ) = 2
  );
$$;

revoke all on function private.ghost_race_arena_link_allowed(uuid,uuid,uuid)
  from public,anon;
grant execute on function private.ghost_race_arena_link_allowed(uuid,uuid,uuid)
  to authenticated;

-- Preserve the existing friend/block/privacy rules. Validate round
-- ownership atomically at INSERT, including for tampered client payloads.
drop policy if exists "friends can send ghost races"
  on public.ghost_race_challenges;
create policy "friends can send ghost races"
on public.ghost_race_challenges
for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and status = 'pending'
  and private.can_send_ghost_race(sender_id,recipient_id)
  and (
    arena_round_id is null
    or private.ghost_race_arena_link_allowed(
      arena_round_id,sender_id,recipient_id
    )
  )
);
comment on column public.ghost_race_challenges.arena_round_id is
  'Optional Arena 1v1 source round, verified at insert. Live results remain participant-reviewed; no automatic points.';
