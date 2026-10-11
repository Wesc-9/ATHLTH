-- Arena phase 1: a member may respond to an invitation but cannot write
-- server-owned score, identity or slot columns through the Data API.
revoke update on table public.arena_series_members from public, anon, authenticated;
grant update (response) on table public.arena_series_members to authenticated;

-- Protect identity from duplicate invitations in concurrent sessions.
create unique index if not exists arena_series_members_live_user_once
on public.arena_series_members(series_id,user_id)
where user_id is not null;
