alter table public.community_group_messages
  add column if not exists sender_name text not null default 'ATHLTH member'
  check (char_length(trim(sender_name)) between 1 and 100);
