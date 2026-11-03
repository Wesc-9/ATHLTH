-- ATHLTH tournament lobby and exercise proposal foundation.
-- RLS: invitation participants can see proposals, accepted athletes can vote/chat.
alter table public.athlth_tournaments
 add column if not exists exercise_mode text not null default 'owner'
   check (exercise_mode in ('owner','open','vote')),
 add column if not exists exercise_count smallint not null default 4
   check (exercise_count between 1 and 12),
 add column if not exists proposals_close_at timestamptz,
 add column if not exists votes_close_at timestamptz,
 add column if not exists approve_player_changes boolean not null default false,
 add column if not exists exercise_selection_finalized_at timestamptz;

alter table public.athlth_tournament_entries
 add column if not exists is_ready boolean not null default false,
 add column if not exists ready_at timestamptz,
 add column if not exists removed_at timestamptz,
 add column if not exists replaced_by uuid references public.profiles(id);

create table if not exists public.athlth_tournament_exercise_candidates (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 exercise_id uuid not null references public.exercise_catalog(id) on delete restrict,
 suggested_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 tie_break_key uuid not null default gen_random_uuid(),
 selected_position smallint,
 unique(tournament_id,exercise_id),
 unique(tournament_id,selected_position),
 unique(id,tournament_id),
 check(selected_position between 1 and 12)
);
create index if not exists athlth_tournament_candidates_by_tourney
 on public.athlth_tournament_exercise_candidates(tournament_id,created_at);
create table if not exists public.athlth_tournament_exercise_votes (
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 candidate_id uuid not null,
 voter_id uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 primary key(candidate_id,voter_id),
 foreign key(candidate_id,tournament_id)
  references public.athlth_tournament_exercise_candidates(id,tournament_id) on delete cascade
);
create index if not exists athlth_tournament_votes_lookup
 on public.athlth_tournament_exercise_votes(tournament_id,voter_id);
create table if not exists public.athlth_tournament_lobby_messages (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 author_id uuid not null references public.profiles(id),
 content text not null check(length(btrim(content)) between 1 and 1000),
 kind text not null default 'chat' check(kind in ('chat','announcement')),
 created_at timestamptz not null default now()
);
create index if not exists athlth_tournament_chat_recent
 on public.athlth_tournament_lobby_messages(tournament_id,created_at desc);

create table if not exists public.athlth_tournament_player_change (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 old_player_id uuid not null references public.profiles(id),
 new_player_id uuid not null references public.profiles(id),
 initiated_by uuid not null references public.profiles(id),
 status text not null default 'pending' check(status in ('pending','applied','rejected','cancelled')),
 new_player_accepted boolean not null default false,
 requires_approval boolean not null default false,
 created_at timestamptz not null default now(),
 applied_at timestamptz,
 check(old_player_id<>new_player_id)
);
create unique index if not exists athlth_tournament_change_pending
 on public.athlth_tournament_player_change(tournament_id,old_player_id)
 where status='pending';

create table if not exists public.athlth_tournament_player_change_votes (
 request_id uuid not null references public.athlth_tournament_player_change(id) on delete cascade,
 voter_id uuid not null references public.profiles(id),
 approved boolean not null,
 voted_at timestamptz not null default now(),
 primary key(request_id,voter_id)
);

create or replace function private.athlth_tournament_is_entrant(p_tournament uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
  exists(select 1 from public.athlth_tournaments t
        where t.id=p_tournament and t.owner_id=auth.uid())
  or exists(select 1 from public.athlth_tournament_entries e
        where e.tournament_id=p_tournament and e.user_id=auth.uid()
          and e.response in ('invited','accepted'))
 );
$$;

create or replace function private.athlth_tournament_is_accepted(p_tournament uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(
  select 1 from public.athlth_tournament_entries e
   where e.tournament_id=p_tournament and e.user_id=auth.uid()
     and e.response='accepted' and e.removed_at is null
 );
$$;

alter table public.athlth_tournament_exercise_candidates enable row level security;
alter table public.athlth_tournament_exercise_votes enable row level security;
alter table public.athlth_tournament_lobby_messages enable row level security;
alter table public.athlth_tournament_player_change enable row level security;
alter table public.athlth_tournament_player_change_votes enable row level security;

create policy "lobby_read_candidates" on public.athlth_tournament_exercise_candidates
 for select to authenticated
 using (private.athlth_tournament_is_entrant(tournament_id));
create policy "lobby_read_votes" on public.athlth_tournament_exercise_votes
 for select to authenticated
 using (private.athlth_tournament_is_entrant(tournament_id));
create policy "lobby_read_messages" on public.athlth_tournament_lobby_messages
 for select to authenticated
 using (private.athlth_tournament_is_entrant(tournament_id));
create policy "lobby_read_changes" on public.athlth_tournament_player_change
 for select to authenticated
 using (private.athlth_tournament_is_entrant(tournament_id)
   or new_player_id=auth.uid());
create policy "lobby_read_change_votes" on public.athlth_tournament_player_change_votes
 for select to authenticated using (
  exists(select 1 from public.athlth_tournament_player_change c
          where c.id=request_id and
          (private.athlth_tournament_is_entrant(c.tournament_id)
           or c.new_player_id=auth.uid()))
 );

revoke all on public.athlth_tournament_exercise_candidates,
 public.athlth_tournament_exercise_votes,public.athlth_tournament_lobby_messages,
 public.athlth_tournament_player_change,public.athlth_tournament_player_change_votes
 from anon,authenticated,public;
grant select on public.athlth_tournament_exercise_candidates,
 public.athlth_tournament_exercise_votes,public.athlth_tournament_lobby_messages,
 public.athlth_tournament_player_change,public.athlth_tournament_player_change_votes
 to authenticated;
revoke all on function private.athlth_tournament_is_entrant(uuid),
 private.athlth_tournament_is_accepted(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.athlth_tournament_is_entrant(uuid),
 private.athlth_tournament_is_accepted(uuid) to authenticated;
