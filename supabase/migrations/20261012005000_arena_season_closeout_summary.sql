-- Club season finish status, without leaking titles, participants,
-- activity traces, or data from inaccessible linked competitions.
-- This is independent of the separately moderated Weekly Challenge.
create or replace function public.arena_club_season_closeout(
  p_season uuid
) returns table (
  linked_competitions bigint,
  incomplete_competitions bigint,
  unresolved_competitions bigint
)
language plpgsql stable security definer
set search_path=pg_catalog,public,private
as $$
declare v_club uuid;
begin
  select s.club_id into v_club
  from public.arena_club_seasons s where s.id=p_season;

  if auth.uid() is null or v_club is null or not exists(
    select 1 from public.community_group_members m
    where m.group_id=v_club and m.user_id=auth.uid()
  ) then
    raise exception 'Club membership required';
  end if;

  return query
  select count(*)::bigint,
         count(*) filter (
           where s.id is null or s.status is distinct from 'completed'
         )::bigint,
         count(*) filter (
           where s.status='completed' and s.completion_reason='deadline_unresolved'
         )::bigint
  from public.arena_club_season_series link
  left join public.arena_series s on s.id=link.series_id
  where link.season_id=p_season;
end;
$$;

revoke all on function public.arena_club_season_closeout(uuid)
  from public,anon;
grant execute on function public.arena_club_season_closeout(uuid)
  to authenticated;
comment on function public.arena_club_season_closeout(uuid) is
  'Only Club member aggregate counts: no details of inaccessible Arena competitions and no automatic champion or points';
