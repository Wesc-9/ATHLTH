-- ATHLTH Arena tournaments: isolated from pre-existing Arena series and social duels.
-- Official results require a proposal from one athlete and a separate approval
-- from their opponent. Practice rounds are never counted or eliminated.
create table if not exists public.athlth_tournaments (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references public.profiles(id) on delete cascade,
    club_id uuid references public.community_groups(id) on delete cascade,
    season_id uuid references public.arena_club_seasons(id) on delete set null,
    title text not null check(length(btrim(title)) between 3 and 80),
    format text not null check(format in ('league','groups','cup')),
    group_size integer not null default 4 check(group_size between 2 and 16),
    qualifiers_per_group integer not null default 2
        check(qualifiers_per_group between 1 and 16),
    win_points integer not null default 3 check(win_points between 1 and 10),
    draw_points integer not null default 1 check(draw_points between 0 and 3),
    status text not null default 'inviting'
        check(status in ('inviting','active','completed','cancelled')),
    created_at timestamptz not null default now(),
    started_at timestamptz,
    completed_at timestamptz,
    check(qualifiers_per_group <= group_size),
    check(season_id is null or club_id is not null)
);

create table if not exists public.athlth_tournament_entries (
    tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
    user_id uuid not null references public.profiles(id) on delete cascade,
    seed integer not null check(seed between 1 and 128),
    response text not null default 'invited'
        check(response in ('invited','accepted','declined')),
    responded_at timestamptz,
    group_index integer,
    primary key(tournament_id,user_id),
    unique(tournament_id,seed)
);

create table if not exists public.athlth_tournament_practice (
    id uuid primary key default gen_random_uuid(),
    tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
    ordinal integer not null check(ordinal between 1 and 12),
    title text not null check(length(btrim(title)) between 1 and 60),
    unique(tournament_id,ordinal)
);

create table if not exists public.athlth_tournament_matches (
    id uuid primary key default gen_random_uuid(),
    tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
    phase text not null check(phase in ('warmup','league','group','cup','playoff')),
    round_number integer not null check(round_number between 1 and 256),
    group_index integer,
    slot_index integer not null check(slot_index between 1 and 512),
    home_id uuid not null references public.profiles(id) on delete restrict,
    away_id uuid references public.profiles(id) on delete restrict,
    home_score numeric(12,3),
    away_score numeric(12,3),
    status text not null default 'scheduled'
        check(status in ('scheduled','proposed','confirmed','disputed')),
    proposed_by uuid references public.profiles(id) on delete set null,
    confirmed_by uuid references public.profiles(id) on delete set null,
    confirmed_at timestamptz,
    evidence_note text not null default '',
    check(home_id is distinct from away_id),
    check((away_id is not null) or (phase in ('cup','playoff'))),
    check((home_score is null and away_score is null) or
          (home_score >= 0 and away_score >= 0)),
    unique(tournament_id,phase,round_number,group_index,slot_index)
);

-- Equality with nullable group_index must be explicit.
create unique index if not exists athlth_tournament_match_slot_uniq
 on public.athlth_tournament_matches(
    tournament_id, phase, round_number,
    coalesce(group_index, -1), slot_index
 );

create table if not exists public.athlth_tournament_audit (
    id uuid primary key default gen_random_uuid(),
    tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
    actor_id uuid references public.profiles(id) on delete set null,
    event text not null check(length(event) between 3 and 45),
    info jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index if not exists athlth_tournament_owner_recent
 on public.athlth_tournaments(owner_id,created_at desc);
create index if not exists athlth_tournament_entries_user
 on public.athlth_tournament_entries(user_id,tournament_id);
create index if not exists athlth_tournament_matches_lookup
 on public.athlth_tournament_matches(tournament_id,phase,round_number,status);
create index if not exists athlth_tournament_club_season
 on public.athlth_tournaments(club_id,season_id);

alter table public.athlth_tournaments enable row level security;
alter table public.athlth_tournament_entries enable row level security;
alter table public.athlth_tournament_practice enable row level security;
alter table public.athlth_tournament_matches enable row level security;
alter table public.athlth_tournament_audit enable row level security;

-- private schema is not exposed as a public PostgREST endpoint.
create schema if not exists private;
create or replace function private.athlth_tournament_can_view(p_tournament uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
    select auth.uid() is not null and exists (
        select 1 from public.athlth_tournaments t
        where t.id=p_tournament and (
            t.owner_id=auth.uid()
            or exists(
                select 1 from public.athlth_tournament_entries e
                where e.tournament_id=t.id and e.user_id=auth.uid()
            )
            or (t.club_id is not null and exists(
                select 1 from public.community_group_members m
                where m.group_id=t.club_id and m.user_id=auth.uid()
            ))
        )
    );
$$;
revoke all on function private.athlth_tournament_can_view(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.athlth_tournament_can_view(uuid) to authenticated;

create policy "tournament_read" on public.athlth_tournaments
    for select to authenticated
    using (private.athlth_tournament_can_view(id));
create policy "tournament_entries_read" on public.athlth_tournament_entries
    for select to authenticated
    using (private.athlth_tournament_can_view(tournament_id));
create policy "tournament_practice_read" on public.athlth_tournament_practice
    for select to authenticated
    using (private.athlth_tournament_can_view(tournament_id));
create policy "tournament_matches_read" on public.athlth_tournament_matches
    for select to authenticated
    using (private.athlth_tournament_can_view(tournament_id));
create policy "tournament_audit_read" on public.athlth_tournament_audit
    for select to authenticated
    using (private.athlth_tournament_can_view(tournament_id));

-- RPCs alone can mutate; clients cannot insert, rewrite or approve directly.
revoke all on public.athlth_tournaments, public.athlth_tournament_entries,
 public.athlth_tournament_practice, public.athlth_tournament_matches,
 public.athlth_tournament_audit from anon, authenticated, public;
grant select on public.athlth_tournaments, public.athlth_tournament_entries,
 public.athlth_tournament_practice, public.athlth_tournament_matches,
 public.athlth_tournament_audit to authenticated;

create or replace function public.athlth_tournament_create(
    p_title text, p_format text, p_club uuid, p_season uuid,
    p_group_size integer, p_qualifiers integer,
    p_invitees uuid[], p_warmup_titles text[]
) returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_id uuid;
    v_invitee uuid;
    v_index integer := 1;
    v_title text;
    v_club_allowed boolean;
    v_warmup text;
begin
    if v_owner is null then raise exception 'Sign in required'; end if;
    if p_title is null or length(btrim(p_title)) not between 3 and 80 or
       p_format not in ('league','groups','cup') or
       p_group_size not between 2 and 16 or
       p_qualifiers not between 1 and p_group_size then
        raise exception 'Invalid tournament settings';
    end if;
    if coalesce(array_length(p_invitees,1),0) < 1 or
       coalesce(array_length(p_invitees,1),0) > 127 or
       coalesce(array_length(p_warmup_titles,1),0) > 12 then
        raise exception 'Invalid participant or warmup count';
    end if;
    if v_owner=any(p_invitees) or
       exists(select 1 from unnest(p_invitees) x
              where x is null) or
       (select count(distinct x) from unnest(p_invitees) x) <>
       coalesce(array_length(p_invitees,1),0) or
       (select count(*) from public.profiles p
        where p.id=any(p_invitees)) <> coalesce(array_length(p_invitees,1),0) then
        raise exception 'Invalid or duplicate invited users';
    end if;
    if p_club is null and p_season is not null then
        raise exception 'Personal tournaments cannot join club seasons';
    end if;
    if p_club is not null then
        select exists(
            select 1 from public.community_group_members m
            where m.group_id=p_club and m.user_id=v_owner
              and m.role='owner'
        ) into v_club_allowed;
        if not v_club_allowed then
            raise exception 'Only club owners may create club tournaments';
        end if;
        if p_season is not null and not exists(
            select 1 from public.arena_club_seasons s
            where s.id=p_season and s.club_id=p_club
                and current_date <= s.ends_on
        ) then
            raise exception 'Season does not belong to this club or has ended';
        end if;
    end if;
    insert into public.athlth_tournaments(
        owner_id, club_id, season_id, title, format,
        group_size, qualifiers_per_group
    ) values (
        v_owner,p_club,p_season,btrim(p_title),p_format,
        p_group_size,p_qualifiers
    ) returning id into v_id;
    insert into public.athlth_tournament_entries(
        tournament_id,user_id,seed,response,responded_at
    ) values(v_id,v_owner,1,'accepted',now());
    foreach v_invitee in array p_invitees loop
        v_index:=v_index+1;
        insert into public.athlth_tournament_entries(
            tournament_id,user_id,seed,response
        ) values(v_id,v_invitee,v_index,'invited');
    end loop;
    v_index:=0;
    foreach v_warmup in array coalesce(p_warmup_titles,array[]::text[]) loop
        if v_warmup is null or length(btrim(v_warmup)) not between 1 and 60 then
            raise exception 'Invalid practice round title';
        end if;
        v_index:=v_index+1;
        insert into public.athlth_tournament_practice(
            tournament_id,ordinal,title
        ) values(v_id,v_index,btrim(v_warmup));
    end loop;
    insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
    values(v_id,v_owner,'created');
    return v_id;
end;
$$;
revoke all on function public.athlth_tournament_create(
 text,text,uuid,uuid,integer,integer,uuid[],text[]) from public,anon;
grant execute on function public.athlth_tournament_create(
 text,text,uuid,uuid,integer,integer,uuid[],text[]) to authenticated;

create or replace function public.athlth_tournament_respond(
    p_tournament uuid, p_accept boolean
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_status text;
begin
    if v_user is null then raise exception 'Sign in required'; end if;
    select status into v_status from public.athlth_tournaments
    where id=p_tournament for update;
    if v_status is distinct from 'inviting' then
        raise exception 'Tournament invitations are closed';
    end if;
    update public.athlth_tournament_entries
       set response=case when p_accept then 'accepted' else 'declined' end,
           responded_at=now()
     where tournament_id=p_tournament and user_id=v_user
       and response='invited';
    if not found then raise exception 'No pending invitation'; end if;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event
    ) values(p_tournament,v_user,
        case when p_accept then 'invitation_accepted'
             else 'invitation_declined' end);
end;
$$;
revoke all on function public.athlth_tournament_respond(uuid,boolean)
 from public,anon;
grant execute on function public.athlth_tournament_respond(uuid,boolean)
 to authenticated;
