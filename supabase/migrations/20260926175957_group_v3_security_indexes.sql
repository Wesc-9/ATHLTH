-- Harden Group v3 RPC exposure and index the new relation lookups.

revoke all on function public.request_community_group_join(uuid)
  from public, anon;
revoke all on function public.respond_community_group_join_request(uuid, uuid, boolean)
  from public, anon;
revoke all on function public.invite_community_group_member(uuid, uuid)
  from public, anon;
revoke all on function public.respond_community_group_invite(uuid, boolean)
  from public, anon;

grant execute on function public.request_community_group_join(uuid)
  to authenticated;
grant execute on function public.respond_community_group_join_request(uuid, uuid, boolean)
  to authenticated;
grant execute on function public.invite_community_group_member(uuid, uuid)
  to authenticated;
grant execute on function public.respond_community_group_invite(uuid, boolean)
  to authenticated;

create index if not exists community_group_event_rsvps_user_idx
  on public.community_group_event_rsvps(user_id);

create index if not exists community_group_invites_invited_by_idx
  on public.community_group_invites(invited_by);

create index if not exists community_group_join_requests_user_idx
  on public.community_group_join_requests(user_id, status, created_at desc);

create index if not exists community_group_join_requests_responded_by_idx
  on public.community_group_join_requests(responded_by)
  where responded_by is not null;

create index if not exists community_group_notification_preferences_user_idx
  on public.community_group_notification_preferences(user_id);
