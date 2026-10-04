-- Add covering indexes for foreign-key columns used heavily by Community
-- and weekly challenge queries, and remove anonymous execute access from the
-- admin-only weekly challenge shift RPC.

create index if not exists community_group_activity_actor_id_idx
  on public.community_group_activity(actor_id);

create index if not exists community_group_announcements_author_id_idx
  on public.community_group_announcements(author_id);

create index if not exists community_group_challenge_participants_user_id_idx
  on public.community_group_challenge_participants(user_id);

create index if not exists community_group_challenges_creator_id_idx
  on public.community_group_challenges(creator_id);

create index if not exists community_group_challenges_organizer_user_id_idx
  on public.community_group_challenges(organizer_user_id);

create index if not exists community_group_content_comments_author_id_idx
  on public.community_group_content_comments(author_id);

create index if not exists community_group_content_hosts_user_id_idx
  on public.community_group_content_hosts(user_id);

create index if not exists community_group_events_creator_id_idx
  on public.community_group_events(creator_id);

create index if not exists community_group_events_organizer_user_id_idx
  on public.community_group_events(organizer_user_id);

create index if not exists community_group_messages_sender_id_idx
  on public.community_group_messages(sender_id);

create index if not exists community_groups_creator_id_idx
  on public.community_groups(creator_id);

create index if not exists official_weekly_challenge_participants_user_id_idx
  on public.official_weekly_challenge_participants(user_id);

create index if not exists official_weekly_challenges_created_by_idx
  on public.official_weekly_challenges(created_by);

revoke execute on function public.shift_official_weekly_challenges_forward(timestamptz)
  from public, anon;

grant execute on function public.shift_official_weekly_challenges_forward(timestamptz)
  to authenticated;
