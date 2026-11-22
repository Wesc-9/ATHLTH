create table if not exists public.athlth_tournament_invite_requests (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 nominee_id uuid not null references public.profiles(id) on delete cascade,
 proposer_id uuid not null references public.profiles(id) on delete cascade,
 state text not null default 'pending' check(state in ('pending','approved','declined')),
 created_at timestamptz not null default now(),
 resolved_at timestamptz
);
create unique index if not exists athlth_tournament_invite_pending_unique
on public.athlth_tournament_invite_requests(tournament_id,nominee_id)
where state='pending';
create table if not exists public.athlth_tournament_invite_votes (
 request_id uuid not null references public.athlth_tournament_invite_requests(id) on delete cascade,
 voter_id uuid not null references public.profiles(id) on delete cascade,
 approved boolean not null,
 created_at timestamptz not null default now(),
 primary key(request_id,voter_id)
);
alter table public.athlth_tournament_invite_requests enable row level security;
alter table public.athlth_tournament_invite_votes enable row level security;
drop policy if exists competition_invite_requests_read on public.athlth_tournament_invite_requests;
create policy competition_invite_requests_read
on public.athlth_tournament_invite_requests
for select to authenticated
using(private.athlth_tournament_can_view(tournament_id));
drop policy if exists competition_invite_votes_read on public.athlth_tournament_invite_votes;
create policy competition_invite_votes_read
on public.athlth_tournament_invite_votes
for select to authenticated
using(exists(select 1 from public.athlth_tournament_invite_requests r
  where r.id=request_id and private.athlth_tournament_can_view(r.tournament_id)));
revoke all on public.athlth_tournament_invite_requests,
public.athlth_tournament_invite_votes from anon,authenticated,public;
grant select on public.athlth_tournament_invite_requests,
public.athlth_tournament_invite_votes to authenticated;