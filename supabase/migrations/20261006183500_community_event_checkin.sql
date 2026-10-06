-- Community event check-in for ATHLTH 1.6.6.
-- Stores only check-in time + method. Device coordinates are never persisted.

alter table public.community_event_participants
  add column if not exists checked_in_at timestamptz,
  add column if not exists check_in_method text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'community_event_checkin_pair_check'
      and conrelid = 'public.community_event_participants'::regclass
  ) then
    alter table public.community_event_participants
      add constraint community_event_checkin_pair_check
      check (
        (checked_in_at is null and check_in_method is null)
        or
        (
          checked_in_at is not null
          and check_in_method in ('proximity', 'manual')
          and attendance_status = 'going'
        )
      );
  end if;
end
$$;

create or replace function public.community_event_normalize_checkin()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.attendance_status <> 'going' then
    new.checked_in_at := null;
    new.check_in_method := null;
  elsif new.check_in_method is not null
        and new.checked_in_at is null then
    new.checked_in_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists community_event_normalize_checkin_trigger
  on public.community_event_participants;

create trigger community_event_normalize_checkin_trigger
before insert or update of attendance_status, check_in_method
on public.community_event_participants
for each row
execute function public.community_event_normalize_checkin();

create index if not exists community_event_checked_in_idx
  on public.community_event_participants (event_id, checked_in_at)
  where checked_in_at is not null;

-- Existing attendance upserts already require UPDATE in practice.
-- Limit client writes to the two user-controlled fields; checked_in_at
-- is set by the trigger so clients cannot choose a timestamp directly.
revoke update on table public.community_event_participants
  from authenticated;

grant update (attendance_status, check_in_method)
  on table public.community_event_participants
  to authenticated;

drop policy if exists community_event_participants_update_own
  on public.community_event_participants;

create policy community_event_participants_update_own
  on public.community_event_participants
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and attendance_status in ('going', 'maybe')
    and (
      check_in_method is null
      or check_in_method in ('proximity', 'manual')
    )
  );
