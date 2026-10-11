-- Arena relay: append-only history of runner-submitted, corrected and withdrawn leg times.
-- All changes still pass through arena_report_relay_leg and award no points.
-- Earlier reports intentionally do not have retroactive history.
create table if not exists public.arena_relay_leg_history (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.arena_series(id) on delete cascade,
  slot_id uuid not null references public.arena_series_members(slot_id) on delete cascade,
  action text not null check (action in ('submitted','corrected','withdrawn')),
  previous_seconds numeric(10,2),
  current_seconds numeric(10,2),
  changed_at timestamptz not null default now(),
  constraint arena_relay_history_values_check check (
    (action = 'submitted' and previous_seconds is null and current_seconds is not null)
    or (action = 'corrected' and previous_seconds is not null and current_seconds is not null
        and previous_seconds <> current_seconds)
    or (action = 'withdrawn' and previous_seconds is not null and current_seconds is null)
  )
);
create index if not exists arena_relay_history_series_idx
  on public.arena_relay_leg_history(series_id, changed_at desc);

alter table public.arena_relay_leg_history enable row level security;
revoke all on public.arena_relay_leg_history from public, anon, authenticated;
grant select on public.arena_relay_leg_history to authenticated;
drop policy if exists arena_relay_history_read on public.arena_relay_leg_history;
create policy arena_relay_history_read on public.arena_relay_leg_history
  for select to authenticated using (private.arena_can_access(series_id));

create or replace function private.arena_append_relay_leg_history()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  old_seconds numeric(10,2);
  new_seconds numeric(10,2);
  change_action text;
  changed_slot uuid;
  changed_series uuid;
begin
  if tg_op = 'INSERT' then
    change_action := 'submitted';
    old_seconds := null;
    new_seconds := new.elapsed_seconds;
    changed_slot := new.slot_id;
    changed_series := new.series_id;
  elsif tg_op = 'UPDATE' then
    if old.elapsed_seconds is not distinct from new.elapsed_seconds then
      return new;
    end if;
    change_action := 'corrected';
    old_seconds := old.elapsed_seconds;
    new_seconds := new.elapsed_seconds;
    changed_slot := new.slot_id;
    changed_series := new.series_id;
  else
    changed_slot := old.slot_id;
    changed_series := old.series_id;
    -- A deleted athlete's whole member slot must not leave audit or
    -- reinsert history as the member cascades to the report table.
    if not exists (
      select 1 from public.arena_series_members where slot_id=changed_slot
    ) then
      return old;
    end if;
    change_action := 'withdrawn';
    old_seconds := old.elapsed_seconds;
    new_seconds := null;
  end if;
  insert into public.arena_relay_leg_history(
    series_id,slot_id,action,previous_seconds,current_seconds
  ) values (
    changed_series,changed_slot,change_action,old_seconds,new_seconds
  );
  return coalesce(new,old);
end;
$$;

revoke all on function private.arena_append_relay_leg_history()
  from public, anon, authenticated;
drop trigger if exists arena_track_relay_leg_change
  on public.arena_relay_leg_reports;
create trigger arena_track_relay_leg_change
  after insert or update or delete on public.arena_relay_leg_reports
  for each row execute function private.arena_append_relay_leg_history();

comment on table public.arena_relay_leg_history is
  'Append-only audit of runner-controlled relay report changes from activation onward. No GPS proof, no automated baton, and no Arena points.';
