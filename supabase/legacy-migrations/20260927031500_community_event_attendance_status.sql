alter table public.community_event_participants
  add column if not exists attendance_status text not null default 'going'
    check (attendance_status in ('going','maybe'));

drop policy if exists community_event_participants_update_own
  on public.community_event_participants;

create policy community_event_participants_update_own
  on public.community_event_participants
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and attendance_status in ('going','maybe')
  );
