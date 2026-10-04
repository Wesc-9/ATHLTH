alter table public.community_group_events
  drop constraint if exists community_group_events_meeting_name_check;

alter table public.community_group_events
  add constraint community_group_events_meeting_name_check
  check (char_length(meeting_name) <= 180);
