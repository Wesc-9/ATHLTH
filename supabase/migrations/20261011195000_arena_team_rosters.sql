-- Arena 2.0 / Teams phase 1: optional, balanced two-team overlays on
-- existing friend/Club series. All points remain approved individual
-- points; teams never create additional score or change Weekly Challenge.
create table if not exists public.arena_series_team_assignments (
  slot_id uuid primary key references public.arena_series_members(slot_id) on delete cascade,
  series_id uuid not null references public.arena_series(id) on delete cascade,
  team_index smallint not null check (team_index in (1,2)),
  assigned_at timestamptz not null default now()
);
create index if not exists arena_team_assignments_series_idx
  on public.arena_series_team_assignments(series_id,team_index);

alter table public.arena_series_team_assignments enable row level security;
revoke all on public.arena_series_team_assignments from public,anon,authenticated;
grant select on public.arena_series_team_assignments to authenticated;
drop policy if exists arena_team_roster_read on public.arena_series_team_assignments;
create policy arena_team_roster_read on public.arena_series_team_assignments
  for select to authenticated
  using (private.arena_can_access(series_id));

-- Only the series organizer can assign teams before competition start.
-- All accepted participant slots must appear exactly once, in balanced
-- teams with at least two members. Empty arrays disable teams in draft.
create or replace function public.arena_save_team_lineup(
  p_series_id uuid,
  p_first_team_slots uuid[],
  p_second_team_slots uuid[]
) returns void
language plpgsql security definer
set search_path = pg_catalog,public,private
as $$
declare
  actor uuid := (select auth.uid());
  current_series public.arena_series%rowtype;
  first_count integer := coalesce(array_length(p_first_team_slots,1),0);
  second_count integer := coalesce(array_length(p_second_team_slots,1),0);
  all_slots uuid[];
  accepted_count integer;
  valid_count integer;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if p_first_team_slots is null or p_second_team_slots is null then
    raise exception 'Specify both team rosters';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_series_id::text));
  select * into current_series from public.arena_series
  where id=p_series_id for update;
  if not found or current_series.owner_id is distinct from actor
     or current_series.status <> 'draft' then
    raise exception 'Only the organizer may edit teams before start';
  end if;
  if first_count=0 and second_count=0 then
    delete from public.arena_series_team_assignments
    where series_id=p_series_id;
    return;
  end if;
  if first_count < 2 or second_count < 2
     or abs(first_count-second_count)>1 or first_count+second_count>50 then
    raise exception 'Teams must be balanced with at least two athletes each';
  end if;
  all_slots := p_first_team_slots || p_second_team_slots;
  if array_position(all_slots,null) is not null
     or (select count(distinct x) from unnest(all_slots) x) <> first_count+second_count then
    raise exception 'Each participant must belong to exactly one team';
  end if;
  select count(*) into accepted_count from public.arena_series_members m
  where m.series_id=p_series_id and m.response='accepted' and m.user_id is not null;
  if accepted_count <> first_count+second_count then
    raise exception 'All accepted athletes must be assigned and invitations resolved';
  end if;
  if exists (
    select 1 from public.arena_series_members m where m.series_id=p_series_id
    and m.response <> 'accepted'
  ) then
    raise exception 'Resolve pending invitations before arranging teams';
  end if;
  select count(*) into valid_count from public.arena_series_members m
  where m.series_id=p_series_id and m.response='accepted'
    and m.slot_id = any(all_slots);
  if valid_count <> first_count+second_count then
    raise exception 'Invalid or unrelated participant in team roster';
  end if;
  delete from public.arena_series_team_assignments where series_id=p_series_id;
  insert into public.arena_series_team_assignments(slot_id,series_id,team_index)
    select unnest(p_first_team_slots),p_series_id,1;
  insert into public.arena_series_team_assignments(slot_id,series_id,team_index)
    select unnest(p_second_team_slots),p_series_id,2;
end;
$$;
revoke all on function public.arena_save_team_lineup(uuid,uuid[],uuid[])
  from public,anon;
grant execute on function public.arena_save_team_lineup(uuid,uuid[],uuid[])
  to authenticated;
comment on table public.arena_series_team_assignments is
  'Optional frozen team roster. Team total is read-only sum of server-approved member points.';
