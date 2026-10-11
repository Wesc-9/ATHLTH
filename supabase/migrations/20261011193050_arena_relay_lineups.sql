-- Arena 2.0 relay planning (stage 1).
-- Each team runs identical, individually named legs on the same agreed
-- route. This is a lineup only: no automatic baton handoff, verified timing
-- or additional team points are introduced by this migration.
create table if not exists public.arena_series_relay_legs (
  slot_id uuid primary key references public.arena_series_members(slot_id) on delete cascade,
  series_id uuid not null references public.arena_series(id) on delete cascade,
  team_index smallint not null check (team_index in (1,2)),
  leg_order smallint not null check (leg_order between 1 and 25),
  route_round_id uuid not null references public.arena_round_proposals(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(series_id,team_index,leg_order)
);
create index if not exists arena_relay_legs_series_idx
  on public.arena_series_relay_legs(series_id,team_index,leg_order);

alter table public.arena_series_relay_legs enable row level security;
revoke all on public.arena_series_relay_legs from public,anon,authenticated;
grant select on public.arena_series_relay_legs to authenticated;

drop policy if exists arena_relay_legs_read
  on public.arena_series_relay_legs;
create policy arena_relay_legs_read
  on public.arena_series_relay_legs
  for select to authenticated
  using (private.arena_can_access(series_id));

-- Updating a team lineup makes any previous baton order invalid.
-- The existing team RPC deletes and re-inserts lineup slots atomically.
create or replace function private.arena_clear_relay_on_roster_change()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
begin
  delete from public.arena_series_relay_legs
  where series_id = coalesce(new.series_id, old.series_id);
  return coalesce(new, old);
end;
$$;
drop trigger if exists arena_clear_relay_on_roster_change
  on public.arena_series_team_assignments;
create trigger arena_clear_relay_on_roster_change
  after insert or update or delete on public.arena_series_team_assignments
  for each row execute function private.arena_clear_relay_on_roster_change();

create or replace function public.arena_save_relay_lineup(
  p_series_id uuid,
  p_route_round_id uuid,
  p_first_team_slots uuid[],
  p_second_team_slots uuid[]
) returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  current_series public.arena_series%rowtype;
  first_count integer := coalesce(array_length(p_first_team_slots,1),0);
  second_count integer := coalesce(array_length(p_second_team_slots,1),0);
  valid_roster_count integer;
  all_slots uuid[];
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if p_first_team_slots is null or p_second_team_slots is null then
    raise exception 'Both relay teams are required';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_series_id::text));
  select * into current_series from public.arena_series
  where id=p_series_id for update;

  if not found or current_series.owner_id is distinct from actor
     or current_series.status <> 'draft'
     or current_series.scope = 'duel' then
    raise exception 'Only the organizer may edit the draft relay';
  end if;

  -- An empty request clears the draft relay; no automatic team changes.
  if first_count=0 and second_count=0 and p_route_round_id is null then
    delete from public.arena_series_relay_legs where series_id=p_series_id;
    return;
  end if;
  if p_route_round_id is null or first_count < 2 or first_count <> second_count
     or first_count > 25 then
    raise exception 'Relay requires equal teams with 2 to 25 legs each';
  end if;
  if not exists (
    select 1 from public.arena_round_proposals r
    where r.id=p_route_round_id and r.series_id=p_series_id
      and r.template='fastestRoute' and r.route_snapshot is not null
  ) then
    raise exception 'Relay must use a route round from this Arena series';
  end if;
  all_slots := p_first_team_slots || p_second_team_slots;
  if array_position(all_slots,null) is not null
     or (select count(distinct slot) from unnest(all_slots) slot)
        <> first_count + second_count then
    raise exception 'Each relay athlete must have exactly one leg';
  end if;
  -- Team and participant membership must be exactly the existing roster.
  select count(*) into valid_roster_count
  from public.arena_series_team_assignments t
  join public.arena_series_members m on m.slot_id=t.slot_id
  where t.series_id=p_series_id
    and m.series_id=p_series_id
    and m.response='accepted' and m.user_id is not null
    and (
      (t.team_index=1 and t.slot_id=any(p_first_team_slots)) or
      (t.team_index=2 and t.slot_id=any(p_second_team_slots))
    );
  if valid_roster_count <> first_count + second_count
     or (select count(*) from public.arena_series_team_assignments
         where series_id=p_series_id) <> first_count + second_count then
    raise exception 'Relay order must use each existing team member once';
  end if;
  delete from public.arena_series_relay_legs where series_id=p_series_id;
  insert into public.arena_series_relay_legs(
    slot_id,series_id,team_index,leg_order,route_round_id
  )
  select slot,p_series_id,1,ord::smallint,p_route_round_id
  from unnest(p_first_team_slots) with ordinality as s(slot,ord);
  insert into public.arena_series_relay_legs(
    slot_id,series_id,team_index,leg_order,route_round_id
  )
  select slot,p_series_id,2,ord::smallint,p_route_round_id
  from unnest(p_second_team_slots) with ordinality as s(slot,ord);
end;
$$;
revoke all on function public.arena_save_relay_lineup(uuid,uuid,uuid[],uuid[])
  from public,anon;
grant execute on function public.arena_save_relay_lineup(uuid,uuid,uuid[],uuid[])
  to authenticated;

comment on table public.arena_series_relay_legs is
  'Draft-only relay baton order on one agreed route. No automatic handoffs or points.';
