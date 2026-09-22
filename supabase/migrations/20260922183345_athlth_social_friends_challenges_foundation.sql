-- ATHLTH Friends, Social and Challenges foundation.
-- Applied to Supabase migration history as 20260922183345.

create schema if not exists private;

create table if not exists public.profile_social_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  profile_visibility text not null default 'friends' check (profile_visibility in ('private','friends','public')),
  discoverable boolean not null default true,
  allow_friend_requests boolean not null default true,
  share_training_presence boolean not null default true,
  share_performance_stats boolean not null default true,
  share_trophy_cabinet boolean not null default true,
  share_goals boolean not null default false,
  share_recent_activity boolean not null default true,
  share_running_prs boolean not null default true,
  share_strength_prs boolean not null default true,
  share_workout_totals boolean not null default true,
  allow_challenge_invites text not null default 'friends' check (allow_challenge_invites in ('friends','everyone','nobody')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_profile_cards (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  username citext,
  display_name text,
  bio text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.social_profile_cards add column if not exists bio text;

create unique index if not exists social_profile_cards_username_idx
  on public.social_profile_cards(username) where username is not null;

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  message text check (message is null or char_length(message) <= 240),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  updated_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create unique index if not exists friend_requests_one_pending_pair_idx
  on public.friend_requests (least(sender_id, recipient_id), greatest(sender_id, recipient_id))
  where status = 'pending';
create index if not exists friend_requests_sender_idx on public.friend_requests(sender_id, status, created_at desc);
create index if not exists friend_requests_recipient_idx on public.friend_requests(recipient_id, status, created_at desc);

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (user_a < user_b),
  unique (user_a, user_b)
);
create index if not exists friendships_user_a_idx on public.friendships(user_a);
create index if not exists friendships_user_b_idx on public.friendships(user_b);

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index if not exists user_blocks_blocked_idx on public.user_blocks(blocked_id);

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('spam','harassment','impersonation','unsafe_content','other')),
  details text check (details is null or char_length(details) <= 1000),
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);
create index if not exists user_reports_reporter_idx on public.user_reports(reporter_id, created_at desc);
create index if not exists user_reports_reported_idx on public.user_reports(reported_id);

create table if not exists public.social_performance_stats (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  fastest_1k_seconds double precision,
  fastest_1k_date timestamptz,
  fastest_5k_seconds double precision,
  fastest_5k_date timestamptz,
  fastest_marathon_seconds double precision,
  fastest_marathon_date timestamptz,
  longest_workout_seconds double precision,
  longest_workout_date timestamptz,
  longest_workout_activity text,
  longest_distance_meters double precision,
  longest_distance_date timestamptz,
  longest_distance_activity text,
  longest_run_meters double precision,
  longest_run_date timestamptz,
  total_workout_count integer not null default 0 check (total_workout_count >= 0),
  total_training_seconds double precision not null default 0 check (total_training_seconds >= 0),
  total_running_distance_meters double precision not null default 0 check (total_running_distance_meters >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_trophy_showcases (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  items jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(items) = 'array')
);

create table if not exists public.social_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  state text not null default 'available' check (state in ('offline','available','training')),
  workout_title text check (workout_title is null or char_length(workout_title) <= 120),
  started_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.social_activities (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('workout','trophy','goal','challenge','personal_record')),
  title text not null check (char_length(title) between 1 and 160),
  subtitle text check (subtitle is null or char_length(subtitle) <= 300),
  metadata jsonb not null default '{}'::jsonb,
  visibility text not null default 'friends' check (visibility in ('private','friends','public')),
  event_key text,
  created_at timestamptz not null default now()
);
alter table public.social_activities add column if not exists event_key text;
create index if not exists social_activities_actor_created_idx on public.social_activities(actor_id, created_at desc);
create index if not exists social_activities_created_idx on public.social_activities(created_at desc);
create unique index if not exists social_activities_actor_event_key_idx
  on public.social_activities(actor_id, event_key) where event_key is not null;

create table if not exists public.social_activity_reactions (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.social_activities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null check (reaction in ('fire','strong','clap')),
  created_at timestamptz not null default now(),
  unique (activity_id, user_id)
);
create index if not exists social_activity_reactions_activity_idx on public.social_activity_reactions(activity_id);
create index if not exists social_activity_reactions_user_idx on public.social_activity_reactions(user_id);

create table if not exists public.social_challenges (
  id uuid primary key,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 160),
  sport text not null check (sport in ('running','strength')),
  status text not null check (status in ('draft','invited','upcoming','active','completed','cancelled')),
  rules jsonb not null,
  visibility text not null default 'friends' check (visibility in ('private','friends','public')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  rules_locked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);
create index if not exists social_challenges_creator_idx on public.social_challenges(creator_id, created_at desc);
create index if not exists social_challenges_window_idx on public.social_challenges(starts_at, ends_at);

create table if not exists public.social_challenge_participants (
  id uuid primary key,
  challenge_id uuid not null references public.social_challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  state text not null check (state in ('creator','invited','accepted','declined')),
  invited_by uuid not null references public.profiles(id) on delete cascade,
  invited_at timestamptz not null default now(),
  responded_at timestamptz,
  unique (challenge_id, user_id)
);
create index if not exists social_challenge_participants_user_idx
  on public.social_challenge_participants(user_id, state, invited_at desc);
create index if not exists social_challenge_participants_invited_by_idx
  on public.social_challenge_participants(invited_by);

create table if not exists public.social_challenge_attempts (
  id uuid primary key,
  challenge_id uuid not null references public.social_challenges(id) on delete cascade,
  participant_id uuid not null references public.social_challenge_participants(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  participant_name text not null,
  verification text not null check (verification in ('appleHealth','athlth','manual')),
  source_workout_id uuid,
  submitted_at timestamptz not null,
  started_at timestamptz,
  ended_at timestamptz,
  duration_seconds double precision,
  distance_meters double precision,
  weight_kilograms double precision,
  reps integer,
  volume_kilograms double precision,
  route_match_percent double precision,
  score double precision not null,
  detail text not null,
  manual_note text,
  is_eligible boolean not null default true,
  ineligibility_reason text
);
create index if not exists social_challenge_attempts_challenge_idx on public.social_challenge_attempts(challenge_id, submitted_at desc);
create index if not exists social_challenge_attempts_user_idx on public.social_challenge_attempts(user_id, submitted_at desc);
create index if not exists social_challenge_attempts_participant_idx on public.social_challenge_attempts(participant_id);
create unique index if not exists social_challenge_attempts_source_idx
  on public.social_challenge_attempts(challenge_id, user_id, source_workout_id)
  where source_workout_id is not null;

create table if not exists public.social_challenge_checkins (
  id uuid primary key,
  challenge_id uuid not null references public.social_challenges(id) on delete cascade,
  participant_id uuid not null references public.social_challenge_participants(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  distance_from_meetup_meters double precision,
  verified_near_meetup boolean not null default false,
  unique (challenge_id, participant_id)
);
create index if not exists social_challenge_checkins_participant_idx on public.social_challenge_checkins(participant_id);
create index if not exists social_challenge_checkins_user_idx on public.social_challenge_checkins(user_id);

create table if not exists public.social_inbox_events (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('friend_request','friend_accepted','challenge_invite','challenge_result','reaction')),
  title text not null,
  message text not null,
  entity_type text,
  entity_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists social_inbox_events_recipient_idx on public.social_inbox_events(recipient_id, read_at, created_at desc);

insert into public.profile_social_settings (user_id, profile_visibility, share_training_presence)
select p.id, coalesce(up.profile_visibility, 'friends'), coalesce(up.share_training_presence, true)
from public.profiles p
left join public.user_preferences up on up.user_id = p.id
on conflict (user_id) do nothing;

insert into public.social_profile_cards (user_id, username, display_name, bio, avatar_url, created_at, updated_at)
select id, username, display_name, bio, avatar_url, created_at, updated_at
from public.profiles
on conflict (user_id) do update
set username = excluded.username,
    display_name = excluded.display_name,
    bio = excluded.bio,
    avatar_url = excluded.avatar_url,
    updated_at = excluded.updated_at;

create or replace function private.sync_social_profile()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  insert into public.profile_social_settings (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.social_profile_cards (user_id, username, display_name, bio, avatar_url, created_at, updated_at)
  values (new.id, new.username, new.display_name, new.bio, new.avatar_url,
          coalesce(new.created_at, now()), coalesce(new.updated_at, now()))
  on conflict (user_id) do update
  set username = excluded.username,
      display_name = excluded.display_name,
      bio = excluded.bio,
      avatar_url = excluded.avatar_url,
      updated_at = excluded.updated_at;

  return new;
end;
$$;

create or replace function private.are_friends(other_user uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1 from public.friendships f
    where (f.user_a = (select auth.uid()) and f.user_b = other_user)
       or (f.user_b = (select auth.uid()) and f.user_a = other_user)
  );
$$;

create or replace function private.is_blocked(other_user uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = (select auth.uid()) and b.blocked_id = other_user)
       or (b.blocked_id = (select auth.uid()) and b.blocker_id = other_user)
  );
$$;

create or replace function private.can_discover_profile(owner_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select (select auth.uid()) = owner_id
    or ((select auth.uid()) is not null
        and not private.is_blocked(owner_id)
        and coalesce((select s.discoverable from public.profile_social_settings s where s.user_id = owner_id), false));
$$;

create or replace function private.can_view_social_profile(owner_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and (
        coalesce((select s.profile_visibility = 'public'
                  from public.profile_social_settings s where s.user_id = owner_id), false)
        or (
          coalesce((select s.profile_visibility = 'friends'
                    from public.profile_social_settings s where s.user_id = owner_id), false)
          and private.are_friends(owner_id)
        )
      )
    );
$$;

create or replace function private.can_view_social_section(owner_id uuid, section_name text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select private.can_view_social_profile(owner_id)
    and (
      (select auth.uid()) = owner_id
      or coalesce((
        select case section_name
          when 'presence' then s.share_training_presence
          when 'performance' then s.share_performance_stats
          when 'trophies' then s.share_trophy_cabinet
          when 'goals' then s.share_goals
          when 'activity' then s.share_recent_activity
          when 'running_prs' then s.share_running_prs
          when 'strength_prs' then s.share_strength_prs
          when 'workout_totals' then s.share_workout_totals
          else false
        end
        from public.profile_social_settings s
        where s.user_id = owner_id
      ), false)
    );
$$;

create or replace function private.can_view_activity(owner_id uuid, activity_visibility text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and (
        activity_visibility = 'public'
        or (activity_visibility = 'friends' and private.are_friends(owner_id))
      )
      and private.can_view_social_section(owner_id, 'activity')
    );
$$;

create or replace function private.is_challenge_creator(challenge_uuid uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1 from public.social_challenges c
    where c.id = challenge_uuid and c.creator_id = (select auth.uid())
  );
$$;

create or replace function private.is_challenge_member(challenge_uuid uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1 from public.social_challenge_participants p
    where p.challenge_id = challenge_uuid
      and p.user_id = (select auth.uid())
      and p.state in ('creator','invited','accepted')
  );
$$;

create or replace function private.can_view_challenge(challenge_uuid uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1 from public.social_challenges c
    where c.id = challenge_uuid
      and (
        c.creator_id = (select auth.uid())
        or private.is_challenge_member(c.id)
        or (c.visibility = 'public' and not private.is_blocked(c.creator_id))
        or (c.visibility = 'friends' and private.are_friends(c.creator_id))
      )
  );
$$;

create or replace function private.can_view_profile_card(owner_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, private
as $$
  select
    (select auth.uid()) = owner_id
    or exists (
      select 1 from public.user_blocks b
      where b.blocker_id = (select auth.uid()) and b.blocked_id = owner_id
    )
    or (
      not private.is_blocked(owner_id)
      and (
        coalesce((select s.discoverable from public.profile_social_settings s where s.user_id = owner_id), false)
        or private.are_friends(owner_id)
        or exists (
          select 1 from public.friend_requests fr
          where ((fr.sender_id = (select auth.uid()) and fr.recipient_id = owner_id)
              or (fr.recipient_id = (select auth.uid()) and fr.sender_id = owner_id))
            and fr.status = 'pending'
        )
        or exists (
          select 1
          from public.social_challenge_participants me
          join public.social_challenge_participants them on them.challenge_id = me.challenge_id
          where me.user_id = (select auth.uid())
            and them.user_id = owner_id
            and me.state in ('creator','invited','accepted')
            and them.state in ('creator','invited','accepted')
        )
      )
    );
$$;

revoke all on function private.sync_social_profile() from public, anon, authenticated;
revoke all on function private.are_friends(uuid) from public, anon;
revoke all on function private.is_blocked(uuid) from public, anon;
revoke all on function private.can_discover_profile(uuid) from public, anon;
revoke all on function private.can_view_social_profile(uuid) from public, anon;
revoke all on function private.can_view_social_section(uuid,text) from public, anon;
revoke all on function private.can_view_activity(uuid,text) from public, anon;
revoke all on function private.is_challenge_creator(uuid) from public, anon;
revoke all on function private.is_challenge_member(uuid) from public, anon;
revoke all on function private.can_view_challenge(uuid) from public, anon;
revoke all on function private.can_view_profile_card(uuid) from public, anon;

grant usage on schema private to authenticated;
grant execute on function private.are_friends(uuid) to authenticated;
grant execute on function private.is_blocked(uuid) to authenticated;
grant execute on function private.can_discover_profile(uuid) to authenticated;
grant execute on function private.can_view_social_profile(uuid) to authenticated;
grant execute on function private.can_view_social_section(uuid,text) to authenticated;
grant execute on function private.can_view_activity(uuid,text) to authenticated;
grant execute on function private.is_challenge_creator(uuid) to authenticated;
grant execute on function private.is_challenge_member(uuid) to authenticated;
grant execute on function private.can_view_challenge(uuid) to authenticated;
grant execute on function private.can_view_profile_card(uuid) to authenticated;

drop trigger if exists profiles_sync_social_profile on public.profiles;
create trigger profiles_sync_social_profile
after insert or update of username, display_name, bio, avatar_url
on public.profiles
for each row execute function private.sync_social_profile();

alter table public.profile_social_settings enable row level security;
alter table public.social_profile_cards enable row level security;
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.user_blocks enable row level security;
alter table public.user_reports enable row level security;
alter table public.social_performance_stats enable row level security;
alter table public.social_trophy_showcases enable row level security;
alter table public.social_presence enable row level security;
alter table public.social_activities enable row level security;
alter table public.social_activity_reactions enable row level security;
alter table public.social_challenges enable row level security;
alter table public.social_challenge_participants enable row level security;
alter table public.social_challenge_attempts enable row level security;
alter table public.social_challenge_checkins enable row level security;
alter table public.social_inbox_events enable row level security;

revoke all on table public.profile_social_settings from anon, authenticated;
revoke all on table public.social_profile_cards from anon, authenticated;
revoke all on table public.friend_requests from anon, authenticated;
revoke all on table public.friendships from anon, authenticated;
revoke all on table public.user_blocks from anon, authenticated;
revoke all on table public.user_reports from anon, authenticated;
revoke all on table public.social_performance_stats from anon, authenticated;
revoke all on table public.social_trophy_showcases from anon, authenticated;
revoke all on table public.social_presence from anon, authenticated;
revoke all on table public.social_activities from anon, authenticated;
revoke all on table public.social_activity_reactions from anon, authenticated;
revoke all on table public.social_challenges from anon, authenticated;
revoke all on table public.social_challenge_participants from anon, authenticated;
revoke all on table public.social_challenge_attempts from anon, authenticated;
revoke all on table public.social_challenge_checkins from anon, authenticated;
revoke all on table public.social_inbox_events from anon, authenticated;

grant select, update on public.profile_social_settings to authenticated;
grant select on public.social_profile_cards to authenticated;
grant select, insert, update on public.friend_requests to authenticated;
grant select, delete on public.friendships to authenticated;
grant select, insert, delete on public.user_blocks to authenticated;
grant select, insert on public.user_reports to authenticated;
grant select, insert, update on public.social_performance_stats to authenticated;
grant select, insert, update on public.social_trophy_showcases to authenticated;
grant select, insert, update on public.social_presence to authenticated;
grant select, insert, update, delete on public.social_activities to authenticated;
grant select, insert, update, delete on public.social_activity_reactions to authenticated;
grant select, insert, update on public.social_challenges to authenticated;
grant select, insert, update on public.social_challenge_participants to authenticated;
grant select, insert on public.social_challenge_attempts to authenticated;
grant select, insert, update on public.social_challenge_checkins to authenticated;
grant select, update, delete on public.social_inbox_events to authenticated;

drop policy if exists social_settings_select_own on public.profile_social_settings;
create policy social_settings_select_own on public.profile_social_settings for select to authenticated
using ((select auth.uid()) = user_id);
drop policy if exists social_settings_update_own on public.profile_social_settings;
create policy social_settings_update_own on public.profile_social_settings for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists social_profile_cards_select_allowed on public.social_profile_cards;
create policy social_profile_cards_select_allowed on public.social_profile_cards for select to authenticated
using (private.can_view_profile_card(user_id));

drop policy if exists friend_requests_select_participant on public.friend_requests;
create policy friend_requests_select_participant on public.friend_requests for select to authenticated
using ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id);
drop policy if exists friend_requests_insert_sender on public.friend_requests;
create policy friend_requests_insert_sender on public.friend_requests for insert to authenticated
with check ((select auth.uid()) = sender_id and status = 'pending');
drop policy if exists friend_requests_update_participant on public.friend_requests;
create policy friend_requests_update_participant on public.friend_requests for update to authenticated
using ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id)
with check ((select auth.uid()) = sender_id or (select auth.uid()) = recipient_id);

drop policy if exists friendships_select_participant on public.friendships;
create policy friendships_select_participant on public.friendships for select to authenticated
using ((select auth.uid()) = user_a or (select auth.uid()) = user_b);
drop policy if exists friendships_delete_participant on public.friendships;
create policy friendships_delete_participant on public.friendships for delete to authenticated
using ((select auth.uid()) = user_a or (select auth.uid()) = user_b);

drop policy if exists user_blocks_select_own on public.user_blocks;
create policy user_blocks_select_own on public.user_blocks for select to authenticated using ((select auth.uid()) = blocker_id);
drop policy if exists user_blocks_insert_own on public.user_blocks;
create policy user_blocks_insert_own on public.user_blocks for insert to authenticated with check ((select auth.uid()) = blocker_id);
drop policy if exists user_blocks_delete_own on public.user_blocks;
create policy user_blocks_delete_own on public.user_blocks for delete to authenticated using ((select auth.uid()) = blocker_id);

drop policy if exists user_reports_select_own on public.user_reports;
create policy user_reports_select_own on public.user_reports for select to authenticated using ((select auth.uid()) = reporter_id);
drop policy if exists user_reports_insert_own on public.user_reports;
create policy user_reports_insert_own on public.user_reports for insert to authenticated with check ((select auth.uid()) = reporter_id);

drop policy if exists social_performance_select_allowed on public.social_performance_stats;
create policy social_performance_select_allowed on public.social_performance_stats for select to authenticated
using (private.can_view_social_section(user_id, 'performance'));
drop policy if exists social_performance_insert_own on public.social_performance_stats;
create policy social_performance_insert_own on public.social_performance_stats for insert to authenticated
with check ((select auth.uid()) = user_id);
drop policy if exists social_performance_update_own on public.social_performance_stats;
create policy social_performance_update_own on public.social_performance_stats for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists social_trophies_select_allowed on public.social_trophy_showcases;
create policy social_trophies_select_allowed on public.social_trophy_showcases for select to authenticated
using (private.can_view_social_section(user_id, 'trophies'));
drop policy if exists social_trophies_insert_own on public.social_trophy_showcases;
create policy social_trophies_insert_own on public.social_trophy_showcases for insert to authenticated
with check ((select auth.uid()) = user_id);
drop policy if exists social_trophies_update_own on public.social_trophy_showcases;
create policy social_trophies_update_own on public.social_trophy_showcases for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists social_presence_select_allowed on public.social_presence;
create policy social_presence_select_allowed on public.social_presence for select to authenticated
using (private.can_view_social_section(user_id, 'presence'));
drop policy if exists social_presence_insert_own on public.social_presence;
create policy social_presence_insert_own on public.social_presence for insert to authenticated
with check ((select auth.uid()) = user_id);
drop policy if exists social_presence_update_own on public.social_presence;
create policy social_presence_update_own on public.social_presence for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists social_activities_select_allowed on public.social_activities;
create policy social_activities_select_allowed on public.social_activities for select to authenticated
using (private.can_view_activity(actor_id, visibility));
drop policy if exists social_activities_insert_own on public.social_activities;
create policy social_activities_insert_own on public.social_activities for insert to authenticated
with check ((select auth.uid()) = actor_id);
drop policy if exists social_activities_update_own on public.social_activities;
create policy social_activities_update_own on public.social_activities for update to authenticated
using ((select auth.uid()) = actor_id) with check ((select auth.uid()) = actor_id);
drop policy if exists social_activities_delete_own on public.social_activities;
create policy social_activities_delete_own on public.social_activities for delete to authenticated
using ((select auth.uid()) = actor_id);

drop policy if exists social_reactions_select_visible on public.social_activity_reactions;
create policy social_reactions_select_visible on public.social_activity_reactions for select to authenticated
using (exists (
  select 1 from public.social_activities a
  where a.id = activity_id and private.can_view_activity(a.actor_id, a.visibility)
));
drop policy if exists social_reactions_insert_own on public.social_activity_reactions;
create policy social_reactions_insert_own on public.social_activity_reactions for insert to authenticated
with check ((select auth.uid()) = user_id and exists (
  select 1 from public.social_activities a
  where a.id = activity_id and private.can_view_activity(a.actor_id, a.visibility)
));
drop policy if exists social_reactions_update_own on public.social_activity_reactions;
create policy social_reactions_update_own on public.social_activity_reactions for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists social_reactions_delete_own on public.social_activity_reactions;
create policy social_reactions_delete_own on public.social_activity_reactions for delete to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists social_challenges_select_allowed on public.social_challenges;
create policy social_challenges_select_allowed on public.social_challenges for select to authenticated
using (private.can_view_challenge(id));
drop policy if exists social_challenges_insert_creator on public.social_challenges;
create policy social_challenges_insert_creator on public.social_challenges for insert to authenticated
with check ((select auth.uid()) = creator_id);
drop policy if exists social_challenges_update_creator on public.social_challenges;
create policy social_challenges_update_creator on public.social_challenges for update to authenticated
using ((select auth.uid()) = creator_id) with check ((select auth.uid()) = creator_id);

drop policy if exists social_challenge_participants_select_allowed on public.social_challenge_participants;
create policy social_challenge_participants_select_allowed on public.social_challenge_participants for select to authenticated
using (private.can_view_challenge(challenge_id));
drop policy if exists social_challenge_participants_insert_creator on public.social_challenge_participants;
create policy social_challenge_participants_insert_creator on public.social_challenge_participants for insert to authenticated
with check (private.is_challenge_creator(challenge_id) and invited_by = (select auth.uid()));
drop policy if exists social_challenge_participants_update_self on public.social_challenge_participants;
create policy social_challenge_participants_update_self on public.social_challenge_participants for update to authenticated
using ((select auth.uid()) = user_id or private.is_challenge_creator(challenge_id))
with check ((select auth.uid()) = user_id or private.is_challenge_creator(challenge_id));

drop policy if exists social_challenge_attempts_select_allowed on public.social_challenge_attempts;
create policy social_challenge_attempts_select_allowed on public.social_challenge_attempts for select to authenticated
using (private.can_view_challenge(challenge_id));
drop policy if exists social_challenge_attempts_insert_self on public.social_challenge_attempts;
create policy social_challenge_attempts_insert_self on public.social_challenge_attempts for insert to authenticated
with check ((select auth.uid()) = user_id and exists (
  select 1 from public.social_challenge_participants p
  where p.id = participant_id
    and p.challenge_id = social_challenge_attempts.challenge_id
    and p.user_id = (select auth.uid())
    and p.state in ('creator','accepted')
));

drop policy if exists social_challenge_checkins_select_allowed on public.social_challenge_checkins;
create policy social_challenge_checkins_select_allowed on public.social_challenge_checkins for select to authenticated
using (private.can_view_challenge(challenge_id));
drop policy if exists social_challenge_checkins_insert_self on public.social_challenge_checkins;
create policy social_challenge_checkins_insert_self on public.social_challenge_checkins for insert to authenticated
with check ((select auth.uid()) = user_id and exists (
  select 1 from public.social_challenge_participants p
  where p.id = participant_id
    and p.challenge_id = social_challenge_checkins.challenge_id
    and p.user_id = (select auth.uid())
    and p.state in ('creator','accepted')
));
drop policy if exists social_challenge_checkins_update_self on public.social_challenge_checkins;
create policy social_challenge_checkins_update_self on public.social_challenge_checkins for update to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists social_inbox_select_own on public.social_inbox_events;
create policy social_inbox_select_own on public.social_inbox_events for select to authenticated
using ((select auth.uid()) = recipient_id);
drop policy if exists social_inbox_update_own on public.social_inbox_events;
create policy social_inbox_update_own on public.social_inbox_events for update to authenticated
using ((select auth.uid()) = recipient_id) with check ((select auth.uid()) = recipient_id);
drop policy if exists social_inbox_delete_own on public.social_inbox_events;
create policy social_inbox_delete_own on public.social_inbox_events for delete to authenticated
using ((select auth.uid()) = recipient_id);

create or replace function private.guard_friend_request()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  allows_requests boolean;
begin
  if tg_op = 'INSERT' then
    if actor is null or actor <> new.sender_id then raise exception 'Friend request sender must match authenticated user'; end if;
    if new.sender_id = new.recipient_id then raise exception 'Cannot send a friend request to yourself'; end if;
    if private.is_blocked(new.recipient_id) then raise exception 'Friend request is not available for this user'; end if;
    if private.are_friends(new.recipient_id) then raise exception 'Users are already friends'; end if;

    select s.allow_friend_requests into allows_requests
    from public.profile_social_settings s where s.user_id = new.recipient_id;

    if coalesce(allows_requests, false) is not true then raise exception 'This user is not accepting friend requests'; end if;

    new.status := 'pending';
    new.responded_at := null;
    return new;
  end if;

  if new.sender_id <> old.sender_id
     or new.recipient_id <> old.recipient_id
     or new.message is distinct from old.message
     or new.created_at <> old.created_at then
    raise exception 'Friend request identity fields are immutable';
  end if;

  if old.status <> 'pending' then raise exception 'Friend request has already been resolved'; end if;

  if actor = old.recipient_id and new.status in ('accepted','declined') then
    new.responded_at := now();
    return new;
  end if;

  if actor = old.sender_id and new.status = 'cancelled' then
    new.responded_at := now();
    return new;
  end if;

  raise exception 'Invalid friend request transition';
end;
$$;
revoke all on function private.guard_friend_request() from public, anon, authenticated;
drop trigger if exists friend_requests_guard on public.friend_requests;
create trigger friend_requests_guard before insert or update on public.friend_requests
for each row execute function private.guard_friend_request();

create or replace function private.after_friend_request_change()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  a uuid;
  b uuid;
  sender_name text;
  recipient_name text;
begin
  if tg_op = 'INSERT' then
    select coalesce(display_name, username::text, 'Someone') into sender_name
    from public.social_profile_cards where user_id = new.sender_id;

    insert into public.social_inbox_events (recipient_id, kind, title, message, entity_type, entity_id)
    values (new.recipient_id, 'friend_request', 'New friend request',
            sender_name || ' wants to be friends on ATHLTH.', 'friend_request', new.id);
    return new;
  end if;

  if old.status = 'pending' and new.status = 'accepted' then
    a := least(new.sender_id, new.recipient_id);
    b := greatest(new.sender_id, new.recipient_id);

    insert into public.friendships (user_a, user_b) values (a, b)
    on conflict (user_a, user_b) do nothing;

    select coalesce(display_name, username::text, 'Your friend') into recipient_name
    from public.social_profile_cards where user_id = new.recipient_id;

    insert into public.social_inbox_events (recipient_id, kind, title, message, entity_type, entity_id)
    values (new.sender_id, 'friend_accepted', 'Friend request accepted',
            recipient_name || ' accepted your friend request.', 'friendship', new.id);
  end if;

  return new;
end;
$$;
revoke all on function private.after_friend_request_change() from public, anon, authenticated;
drop trigger if exists friend_requests_after_change on public.friend_requests;
create trigger friend_requests_after_change after insert or update of status on public.friend_requests
for each row execute function private.after_friend_request_change();

create or replace function private.after_block_created()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
begin
  delete from public.friendships
  where user_a = least(new.blocker_id, new.blocked_id)
    and user_b = greatest(new.blocker_id, new.blocked_id);

  delete from public.friend_requests
  where status = 'pending'
    and (
      (sender_id = new.blocker_id and recipient_id = new.blocked_id)
      or (sender_id = new.blocked_id and recipient_id = new.blocker_id)
    );

  return new;
end;
$$;
revoke all on function private.after_block_created() from public, anon, authenticated;
drop trigger if exists user_blocks_after_insert on public.user_blocks;
create trigger user_blocks_after_insert after insert on public.user_blocks
for each row execute function private.after_block_created();

create or replace function private.guard_challenge_participant()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  actor uuid := (select auth.uid());
  creator uuid;
  target_setting text;
begin
  select c.creator_id into creator
  from public.social_challenges c
  where c.id = coalesce(new.challenge_id, old.challenge_id);

  if creator is null then raise exception 'Challenge not found'; end if;

  if tg_op = 'INSERT' then
    if actor <> creator or new.invited_by <> actor then raise exception 'Only the challenge creator can add participants'; end if;

    if new.user_id = creator then
      if new.state <> 'creator' then raise exception 'Creator participant must use creator state'; end if;
      return new;
    end if;

    if new.state <> 'invited' then raise exception 'New participants must start as invited'; end if;
    if private.is_blocked(new.user_id) then raise exception 'Challenge invitation is not available for this user'; end if;

    select s.allow_challenge_invites into target_setting
    from public.profile_social_settings s where s.user_id = new.user_id;

    if coalesce(target_setting, 'nobody') = 'nobody' then raise exception 'This user is not accepting challenge invites'; end if;
    if target_setting = 'friends' and not private.are_friends(new.user_id) then raise exception 'This user only accepts challenge invites from friends'; end if;

    return new;
  end if;

  if new.id <> old.id
     or new.challenge_id <> old.challenge_id
     or new.user_id <> old.user_id
     or new.invited_by <> old.invited_by
     or new.invited_at <> old.invited_at then
    raise exception 'Challenge participant identity fields are immutable';
  end if;

  if actor = creator and new.state = old.state and new.responded_at is not distinct from old.responded_at then
    return new;
  end if;

  if actor <> old.user_id or old.state <> 'invited' or new.state not in ('accepted','declined') then
    raise exception 'Invalid challenge invitation transition';
  end if;

  new.responded_at := now();
  return new;
end;
$$;
revoke all on function private.guard_challenge_participant() from public, anon, authenticated;
drop trigger if exists social_challenge_participants_guard on public.social_challenge_participants;
create trigger social_challenge_participants_guard before insert or update on public.social_challenge_participants
for each row execute function private.guard_challenge_participant();

create or replace function private.guard_challenge_update()
returns trigger language plpgsql security invoker
set search_path = pg_catalog, public, private
as $$
begin
  if old.rules_locked_at is not null or now() >= old.starts_at then
    if new.rules is distinct from old.rules
       or new.sport <> old.sport
       or new.starts_at <> old.starts_at
       or new.ends_at is distinct from old.ends_at then
      raise exception 'Challenge rules are locked';
    end if;

    if new.rules_locked_at is null then new.rules_locked_at := old.starts_at; end if;
  end if;

  return new;
end;
$$;
revoke all on function private.guard_challenge_update() from public, anon, authenticated;
drop trigger if exists social_challenges_guard_update on public.social_challenges;
create trigger social_challenges_guard_update before update on public.social_challenges
for each row execute function private.guard_challenge_update();

create or replace function private.challenge_participant_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  challenge_title text;
  inviter_name text;
begin
  if new.state <> 'invited' then return new; end if;

  select c.title into challenge_title from public.social_challenges c where c.id = new.challenge_id;
  select coalesce(p.display_name, p.username::text, 'A friend') into inviter_name
  from public.social_profile_cards p where p.user_id = new.invited_by;

  insert into public.social_inbox_events (recipient_id, kind, title, message, entity_type, entity_id)
  values (new.user_id, 'challenge_invite', 'New challenge',
          inviter_name || ' challenged you: ' || coalesce(challenge_title, 'ATHLTH Challenge'),
          'challenge', new.challenge_id);

  return new;
end;
$$;
revoke all on function private.challenge_participant_event() from public, anon, authenticated;
drop trigger if exists social_challenge_participants_event on public.social_challenge_participants;
create trigger social_challenge_participants_event after insert on public.social_challenge_participants
for each row execute function private.challenge_participant_event();

create or replace function private.challenge_attempt_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  challenge_title text;
begin
  select c.title into challenge_title from public.social_challenges c where c.id = new.challenge_id;

  insert into public.social_inbox_events (recipient_id, kind, title, message, entity_type, entity_id)
  select p.user_id, 'challenge_result', 'New challenge result',
         new.participant_name || ' posted ' || new.detail || ' in ' || coalesce(challenge_title, 'a challenge') || '.',
         'challenge', new.challenge_id
  from public.social_challenge_participants p
  where p.challenge_id = new.challenge_id
    and p.user_id <> new.user_id
    and p.state in ('creator','accepted');

  return new;
end;
$$;
revoke all on function private.challenge_attempt_event() from public, anon, authenticated;
drop trigger if exists social_challenge_attempts_event on public.social_challenge_attempts;
create trigger social_challenge_attempts_event after insert on public.social_challenge_attempts
for each row execute function private.challenge_attempt_event();

create or replace function private.reaction_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  owner_id uuid;
  reactor_name text;
begin
  select a.actor_id into owner_id from public.social_activities a where a.id = new.activity_id;
  if owner_id is null or owner_id = new.user_id then return new; end if;

  select coalesce(p.display_name, p.username::text, 'A friend') into reactor_name
  from public.social_profile_cards p where p.user_id = new.user_id;

  insert into public.social_inbox_events (recipient_id, kind, title, message, entity_type, entity_id)
  values (owner_id, 'reaction', 'New reaction',
          reactor_name || ' reacted to your ATHLTH activity.', 'activity', new.activity_id);

  return new;
end;
$$;
revoke all on function private.reaction_event() from public, anon, authenticated;
drop trigger if exists social_activity_reactions_event on public.social_activity_reactions;
create trigger social_activity_reactions_event after insert on public.social_activity_reactions
for each row execute function private.reaction_event();

drop trigger if exists profile_social_settings_updated_at on public.profile_social_settings;
create trigger profile_social_settings_updated_at
before update on public.profile_social_settings
for each row execute function public.set_updated_at();

drop trigger if exists friend_requests_updated_at on public.friend_requests;
create trigger friend_requests_updated_at
before update on public.friend_requests
for each row execute function public.set_updated_at();

drop trigger if exists social_challenges_updated_at on public.social_challenges;
create trigger social_challenges_updated_at
before update on public.social_challenges
for each row execute function public.set_updated_at();
