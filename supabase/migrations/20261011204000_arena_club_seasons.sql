-- Arena 2.0 – Club seasons. Existing Club/Weekly Challenges are unchanged.
-- Only server-approved Arena member points are included. No GPS/Health data.
create table if not exists public.arena_club_seasons (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.community_groups(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 3 and 80),
  starts_on date not null,
  ends_on date not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (ends_on > starts_on and ends_on - starts_on between 7 and 366)
);
create index if not exists arena_club_seasons_club_idx
  on public.arena_club_seasons(club_id,starts_on desc);

create table if not exists public.arena_club_season_series (
  season_id uuid not null references public.arena_club_seasons(id) on delete cascade,
  series_id uuid not null references public.arena_series(id) on delete cascade,
  linked_at timestamptz not null default now(),
  linked_by uuid not null references auth.users(id) on delete restrict,
  primary key (season_id,series_id),
  unique (series_id)
);

alter table public.arena_club_seasons enable row level security;
alter table public.arena_club_season_series enable row level security;
revoke all on public.arena_club_seasons,public.arena_club_season_series
  from public,anon,authenticated;
grant select on public.arena_club_seasons,public.arena_club_season_series
  to authenticated;

drop policy if exists arena_club_season_read on public.arena_club_seasons;
create policy arena_club_season_read on public.arena_club_seasons
  for select to authenticated
  using (exists (
    select 1 from public.community_group_members m
    where m.group_id=club_id and m.user_id=(select auth.uid())
  ));

drop policy if exists arena_club_season_series_read on public.arena_club_season_series;
create policy arena_club_season_series_read on public.arena_club_season_series
  for select to authenticated
  using (exists (
    select 1 from public.arena_club_seasons season
    join public.community_group_members m on m.group_id=season.club_id
    where season.id=season_id and m.user_id=(select auth.uid())
  ));

create or replace function public.arena_create_club_season(
  p_club uuid,p_title text,p_starts_on date,p_ends_on date
) returns uuid
language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_id uuid; v_name text:=btrim(p_title);
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_club is null or not private.can_manage_community_group(p_club) then
    raise exception 'Club administrator access required';
  end if;
  if v_name is null or char_length(v_name) not between 3 and 80
     or p_starts_on is null or p_ends_on is null
     or p_ends_on-p_starts_on not between 7 and 366 then
    raise exception 'Invalid Club Arena season duration or name';
  end if;
  insert into public.arena_club_seasons(club_id,title,starts_on,ends_on,created_by)
  values (p_club,v_name,p_starts_on,p_ends_on,v_actor)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.arena_attach_club_season_series(
  p_season uuid,p_series uuid
) returns void
language plpgsql security definer
set search_path=pg_catalog,public,private
as $$
declare v_actor uuid:=auth.uid(); v_season public.arena_club_seasons%rowtype;
        v_series public.arena_series%rowtype;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_season from public.arena_club_seasons where id=p_season for update;
  if not found or not private.can_manage_community_group(v_season.club_id) then
    raise exception 'Club administrator access required';
  end if;
  if now()::date > v_season.ends_on then
    raise exception 'Season has ended';
  end if;
  select * into v_series from public.arena_series where id=p_series;
  if not found or v_series.scope<>'club'
     or v_series.club_id is distinct from v_season.club_id
     or coalesce(v_series.starts_at,v_series.created_at)::date
         not between v_season.starts_on and v_season.ends_on
     or (v_series.ends_at is not null and v_series.ends_at::date>v_season.ends_on)
  then
    raise exception 'Series must be from the same Club and inside season dates';
  end if;
  if (select count(*) from public.arena_club_season_series where season_id=p_season)>=30 then
    raise exception 'Too many competitions in a season';
  end if;
  insert into public.arena_club_season_series(season_id,series_id,linked_by)
  values(p_season,p_series,v_actor)
  on conflict (season_id,series_id) do nothing;
end $$;

-- The only scoreboard API. A user must currently belong to the Club.
-- Live/draft self-declared results are NOT counted until they appear in
-- server-settled arena_series_members.points.
create or replace function public.arena_club_season_standings(p_season uuid)
returns table (user_id uuid, points numeric, competitions bigint)
language plpgsql stable security definer
set search_path=pg_catalog,public,private
as $$
declare v_club uuid;
begin
  select club_id into v_club from public.arena_club_seasons where id=p_season;
  if v_club is null or auth.uid() is null
     or not exists(
       select 1 from public.community_group_members m
       where m.group_id=v_club and m.user_id=auth.uid()
     ) then
     raise exception 'Club membership required';
  end if;
  return query
  select m.user_id,sum(m.points)::numeric,count(distinct s.id)::bigint
  from public.arena_club_season_series link
  join public.arena_series s on s.id=link.series_id
  join public.arena_series_members m on m.series_id=s.id
  where link.season_id=p_season
    and s.scope='club' and s.club_id=v_club
    and s.status in ('active','completed')
    and m.user_id is not null and m.response='accepted'
  group by m.user_id
  order by sum(m.points) desc,count(distinct s.id) desc,m.user_id;
end $$;

revoke all on function public.arena_create_club_season(uuid,text,date,date),
  public.arena_attach_club_season_series(uuid,uuid),
  public.arena_club_season_standings(uuid) from public,anon;
grant execute on function public.arena_create_club_season(uuid,text,date,date),
  public.arena_attach_club_season_series(uuid,uuid),
  public.arena_club_season_standings(uuid) to authenticated;

comment on table public.arena_club_seasons is
  'Opt-in Club Arena seasons; editorial Weekly Challenge is unrelated.';
