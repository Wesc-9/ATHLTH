create table if not exists public.athlth_competition_live_positions (
 tournament_id uuid not null references public.athlth_tournaments(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 latitude double precision not null check(latitude between -90 and 90),
 longitude double precision not null check(longitude between -180 and 180),
 accuracy_meters double precision not null check(accuracy_meters between 0 and 30),
 expires_at timestamptz not null,
 updated_at timestamptz not null default now(),
 primary key(tournament_id,user_id)
);
alter table public.athlth_competition_live_positions enable row level security;
revoke all on public.athlth_competition_live_positions from public, anon, authenticated;
grant select on public.athlth_competition_live_positions to authenticated;
drop policy if exists athlth_competition_live_positions_reciprocal on public.athlth_competition_live_positions;
create policy athlth_competition_live_positions_reciprocal
on public.athlth_competition_live_positions
for select to authenticated
using (
 expires_at > clock_timestamp()
 and exists (
  select 1 from public.athlth_tournaments t
  where t.id=tournament_id and t.status='active'
   and t.race_rules->>'allowOptInLiveLocation'='true'
 )
 and private.athlth_tournament_is_accepted(tournament_id)
 and exists (
  select 1 from public.athlth_competition_live_positions own
  where own.tournament_id=tournament_id and own.user_id=(select auth.uid())
    and own.expires_at>clock_timestamp()
 )
);
-- Avoid recursive RLS in the reciprocity clause by looking up the caller's
-- opt-in row only via a private security-definer helper.
create or replace function private.athlth_competition_is_location_sharing(
 p_tournament uuid,p_viewer uuid)
returns boolean language sql stable security definer set search_path='' as $func$
 select exists(
  select 1 from public.athlth_competition_live_positions p
  where p.tournament_id=p_tournament
   and p.user_id=p_viewer and p.expires_at>clock_timestamp()
 );$func$;
revoke all on function private.athlth_competition_is_location_sharing(uuid,uuid)
 from public,anon,authenticated;
drop policy if exists athlth_competition_live_positions_reciprocal on public.athlth_competition_live_positions;
create policy athlth_competition_live_positions_reciprocal
on public.athlth_competition_live_positions
for select to authenticated
using (
 expires_at > clock_timestamp()
 and exists (
  select 1 from public.athlth_tournaments t
  where t.id=tournament_id and t.status='active'
   and t.race_rules->>'allowOptInLiveLocation'='true'
 )
 and private.athlth_tournament_is_accepted(tournament_id)
 and private.athlth_competition_is_location_sharing(
    tournament_id,(select auth.uid()))
);
create or replace function public.athlth_competition_share_live_position(
 p_tournament uuid,p_latitude double precision,p_longitude double precision,
 p_accuracy double precision)
returns void language plpgsql security definer set search_path='' as $func$
declare v_t public.athlth_tournaments%rowtype;
begin
 if auth.uid() is null or
   p_latitude not between -90 and 90 or
   p_longitude not between -180 and 180 or
   p_accuracy not between 0 and 30 then
  raise exception 'Invalid location report'; end if;
 select * into v_t from public.athlth_tournaments
 where id=p_tournament;
 if not found or v_t.status<>'active' or
    v_t.race_rules->>'allowOptInLiveLocation'<>'true' or
    not private.athlth_tournament_is_accepted(p_tournament) then
    raise exception 'Live sharing is not enabled for this participant'; end if;
 insert into public.athlth_competition_live_positions (
  tournament_id,user_id,latitude,longitude,accuracy_meters,updated_at,expires_at)
 values (p_tournament,auth.uid(),p_latitude,p_longitude,p_accuracy,
         clock_timestamp(),clock_timestamp()+interval '25 seconds')
 on conflict(tournament_id,user_id) do update set
 latitude=excluded.latitude,longitude=excluded.longitude,
 accuracy_meters=excluded.accuracy_meters,updated_at=excluded.updated_at,
 expires_at=excluded.expires_at;
end;$func$;
create or replace function public.athlth_competition_stop_live_position(
 p_tournament uuid)
returns void language plpgsql security definer set search_path='' as $func$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.athlth_competition_live_positions
 where tournament_id=p_tournament and user_id=auth.uid();
end;$func$;
revoke all on function public.athlth_competition_share_live_position(uuid,double precision,double precision,double precision) from public,anon;
grant execute on function public.athlth_competition_share_live_position(uuid,double precision,double precision,double precision) to authenticated;
revoke all on function public.athlth_competition_stop_live_position(uuid) from public,anon;
grant execute on function public.athlth_competition_stop_live_position(uuid) to authenticated;
-- RLS evaluates this helper as the authenticated athlete; it must be callable.
grant execute on function private.athlth_competition_is_location_sharing(uuid,uuid) to authenticated;
