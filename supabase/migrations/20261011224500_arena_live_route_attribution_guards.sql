-- A Live Ghost invitation must not claim results for an unrelated Arena
-- course. This is an attribution guard, NOT GPS proof and NOT automatic scoring.
-- Preserve the existing membership/privacy check as a separate mandatory test.
create or replace function private.ghost_race_arena_route_compatible(
  p_round_id uuid,
  p_source_kind text,
  p_distance_meters double precision
) returns boolean
language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1
    from public.arena_round_proposals r
    where r.id = p_round_id
      and r.template = 'fastestRoute'
      and r.route_snapshot is not null
      and r.target_distance_meters between 100 and 500000
      and p_source_kind = 'planned_route'
      and p_distance_meters between 100 and 500000
      -- Existing Live Ghost settings may trim 250 m at either end.
      -- A bounded allowance accommodates this privacy-preserving trim,
      -- without claiming independent route matching.
      and abs(p_distance_meters - r.target_distance_meters)
          <= greatest(550, r.target_distance_meters * 0.07)
  );
$$;

revoke all on function private.ghost_race_arena_route_compatible(uuid,text,double precision)
  from public, anon;
grant execute on function private.ghost_race_arena_route_compatible(uuid,text,double precision)
  to authenticated;

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
    or (
      private.ghost_race_arena_link_allowed(
        arena_round_id,sender_id,recipient_id
      )
      and private.ghost_race_arena_route_compatible(
        arena_round_id,source_kind,distance_meters
      )
    )
  )
);
