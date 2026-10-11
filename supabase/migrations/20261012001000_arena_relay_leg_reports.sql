-- Arena relay stage 2: participant-reported leg times.
-- No device verification, baton handoff or automatic Arena points.
-- Reports belong to the frozen draft relay order and are cleared if that
-- order is removed while the series is still a draft.
create table if not exists public.arena_relay_leg_reports (
  slot_id uuid primary key references public.arena_series_relay_legs(slot_id) on delete cascade,
  series_id uuid not null references public.arena_series(id) on delete cascade,
  elapsed_seconds numeric(10,2) not null
    check (elapsed_seconds >= 10 and elapsed_seconds <= 86400),
  submitted_at timestamptz not null default now()
);

create index if not exists arena_relay_reports_series_idx
  on public.arena_relay_leg_reports(series_id,submitted_at desc);

alter table public.arena_relay_leg_reports enable row level security;
revoke all on public.arena_relay_leg_reports from public,anon,authenticated;
grant select on public.arena_relay_leg_reports to authenticated;

drop policy if exists arena_relay_reports_read on public.arena_relay_leg_reports;
create policy arena_relay_reports_read on public.arena_relay_leg_reports
for select to authenticated
using (private.arena_can_access(series_id));

-- The assigned runner alone may submit or withdraw their own time,
-- during the active competition. No arbitrary slot reassignment,
-- unauthorized editing or automatic point updates.
create or replace function public.arena_report_relay_leg(
  p_series_id uuid,
  p_slot_id uuid,
  p_elapsed_seconds numeric
) returns void
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  active_series public.arena_series%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(hashtext(p_series_id::text));
  select * into active_series
  from public.arena_series
  where id=p_series_id for update;

  if not found or active_series.status <> 'active'
     or (active_series.ends_at is not null and now() > active_series.ends_at) then
    raise exception 'Only active relay competitions accept leg reports';
  end if;

  if not exists (
    select 1 from public.arena_series_relay_legs l
    join public.arena_series_members m
      on m.series_id=l.series_id and m.slot_id=l.slot_id
    join public.arena_series_team_assignments t
      on t.series_id=l.series_id and t.slot_id=l.slot_id
         and t.team_index=l.team_index
    where l.series_id=p_series_id and l.slot_id=p_slot_id
      and m.user_id=actor and m.response='accepted'
  ) then
    raise exception 'Only the assigned active relay runner can report this leg';
  end if;

  if p_elapsed_seconds is null then
    delete from public.arena_relay_leg_reports
    where series_id=p_series_id and slot_id=p_slot_id;
    return;
  end if;

  if p_elapsed_seconds < 10 or p_elapsed_seconds > 86400 then
    raise exception 'Relay leg time must be between 10 seconds and 24 hours';
  end if;

  insert into public.arena_relay_leg_reports
    (slot_id,series_id,elapsed_seconds)
  values (p_slot_id,p_series_id,p_elapsed_seconds)
  on conflict (slot_id)
    do update set
      elapsed_seconds=excluded.elapsed_seconds,
      submitted_at=now();
end;
$$;

revoke all on function public.arena_report_relay_leg(uuid,uuid,numeric)
  from public,anon;
grant execute on function public.arena_report_relay_leg(uuid,uuid,numeric)
  to authenticated;

comment on table public.arena_relay_leg_reports is
  'Voluntarily supplied relay leg times only. Not GPS-verified and never awards Arena points automatically.';
