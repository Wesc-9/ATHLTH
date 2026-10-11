-- Arena relay: opt-in, one-time handoff reminder to the next scheduled runner.
-- This is NOT a live baton transfer and never starts a workout or grants points.
-- Store only frozen lineup slot IDs; account deletion remains covered by FKs.
create table if not exists public.arena_relay_next_runner_notices (
  from_slot_id uuid primary key references public.arena_series_relay_legs(slot_id) on delete cascade,
  to_slot_id uuid not null references public.arena_series_relay_legs(slot_id) on delete cascade,
  series_id uuid not null references public.arena_series(id) on delete cascade,
  sent_at timestamptz not null default now(),
  check (from_slot_id <> to_slot_id)
);

create index if not exists arena_relay_next_notices_series_idx
  on public.arena_relay_next_runner_notices(series_id);

alter table public.arena_relay_next_runner_notices enable row level security;
revoke all on public.arena_relay_next_runner_notices from public, anon, authenticated;

create or replace function public.arena_notify_next_relay_runner(
  p_series_id uuid,
  p_from_slot_id uuid
) returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  leg public.arena_series_relay_legs%rowtype;
  next_leg public.arena_series_relay_legs%rowtype;
  recipient uuid;
  series_title text;
  inserted_rows integer;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if p_series_id is null or p_from_slot_id is null then
    raise exception 'A relay series and reported leg are required';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_series_id::text));

  select l.* into leg
  from public.arena_series_relay_legs l
  join public.arena_series_members m
    on m.slot_id = l.slot_id and m.series_id = l.series_id
  join public.arena_series s on s.id = l.series_id
  where l.series_id = p_series_id and l.slot_id = p_from_slot_id
    and m.user_id = actor and m.response = 'accepted'
    and s.status = 'active'
    and (s.ends_at is null or now() <= s.ends_at);
  if not found then
    raise exception 'Only the active, assigned runner can send a relay reminder';
  end if;

  -- No reminder until every earlier leg of this team has been reported.
  if exists (
    select 1
    from public.arena_series_relay_legs earlier
    left join public.arena_relay_leg_reports report
      on report.series_id=earlier.series_id
      and report.slot_id=earlier.slot_id
    where earlier.series_id=p_series_id
      and earlier.team_index=leg.team_index
      and earlier.leg_order<=leg.leg_order
      and report.slot_id is null
  ) then
    raise exception 'Report this and all preceding legs before notifying the next runner';
  end if;

  select l.* into next_leg
  from public.arena_series_relay_legs l
  where l.series_id=p_series_id
    and l.team_index=leg.team_index
    and l.leg_order=leg.leg_order+1;
  if not found then return false; end if;

  -- A reminder is not meaningful after the next runner has already reported.
  if exists (
    select 1 from public.arena_relay_leg_reports
    where series_id=p_series_id and slot_id=next_leg.slot_id
  ) then return false; end if;

  select m.user_id into recipient
  from public.arena_series_members m
  join public.arena_series_team_assignments t
    on t.series_id=m.series_id and t.slot_id=m.slot_id
  where m.series_id=p_series_id
    and m.slot_id=next_leg.slot_id
    and m.response='accepted'
    and t.team_index=next_leg.team_index
    and m.user_id is not null;
  if recipient is null or recipient=actor then
    raise exception 'Next relay runner is not available';
  end if;

  -- Protect against repeated taps, reconnects and corrections of a report.
  insert into public.arena_relay_next_runner_notices(
    from_slot_id,to_slot_id,series_id
  ) values (p_from_slot_id,next_leg.slot_id,p_series_id)
  on conflict (from_slot_id) do nothing;
  get diagnostics inserted_rows = row_count;
  if inserted_rows=0 then return false; end if;

  select title into series_title
  from public.arena_series where id=p_series_id;

  insert into public.social_inbox_events(
    recipient_id,kind,title,message,entity_type,entity_id,actor_id
  ) values (
    recipient,'arena_round','ATHLTH Arena · stafett',
    'Etappen foran deg er registrert i ' ||
      left(coalesce(series_title,'Arena'),80) ||
      '. Din etappe er neste i planen for lag ' ||
      next_leg.team_index::text ||
      '. Se Arena før du starter.',
    'arena_series',p_series_id,actor
  );

  return true;
end;
$$;

revoke all on function public.arena_notify_next_relay_runner(uuid,uuid)
  from public,anon;
grant execute on function public.arena_notify_next_relay_runner(uuid,uuid)
  to authenticated;

comment on table public.arena_relay_next_runner_notices is
  'One opt-in inbox reminder per preceding frozen relay slot; never GPS-verified or an automatic baton handoff.';
