CREATE OR REPLACE FUNCTION public.athlth_tournament_season_scores(p_season uuid)
 RETURNS TABLE(user_id uuid, points numeric, competitions bigint)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
    select e.user_id,
        coalesce(sum(scoring.points),0)::numeric as points,
        count(distinct t.id)::bigint as competitions
    from public.athlth_tournaments t
    join public.arena_club_seasons s
      on s.id=t.season_id and s.club_id=t.club_id
    join public.athlth_tournament_entries e
      on e.tournament_id=t.id and e.response='accepted'
    cross join lateral (
        select coalesce(sum(
            case
                when m.phase in ('cup','playoff') then
                    case
                        when (m.home_id=e.user_id and m.home_score>m.away_score) or
                             (m.away_id=e.user_id and m.away_score>m.home_score)
                        then t.win_points else 0 end
                when m.home_score=m.away_score then t.draw_points
                when (m.home_id=e.user_id and m.home_score>m.away_score) or
                     (m.away_id=e.user_id and m.away_score>m.home_score)
                then t.win_points else 0
            end
        ),0)::numeric as points
        from public.athlth_tournament_matches m
        where m.tournament_id=t.id
          and m.phase in ('league','group','cup','playoff')
          and m.status='confirmed'
          and m.away_id is not null
          and (not t.competition_settings_applied
            or t.format not in ('league','groups')
            or t.status='completed'
            or not exists(
                select 1 from public.athlth_tournament_matches pending
                where pending.tournament_id=m.tournament_id
                  and pending.phase=m.phase
                  and pending.round_number=m.round_number
                  and pending.group_index is not distinct from m.group_index
                  and pending.away_id is not null
                  and pending.status<>'confirmed'))
          and (m.home_id=e.user_id or m.away_id=e.user_id)
    ) scoring
    where t.season_id=p_season
      and t.status in ('active','completed')
      and auth.uid() is not null
      and exists(
          select 1 from public.community_group_members member
          where member.group_id=s.club_id and member.user_id=auth.uid()
      )
    group by e.user_id
    order by points desc,e.user_id;
$function$
;
revoke all on function public.athlth_tournament_season_scores(uuid) from public,anon;
grant execute on function public.athlth_tournament_season_scores(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.athlth_tournament_season_standings(p_season uuid)
 RETURNS TABLE(user_id uuid, username text, matches bigint, wins bigint, season_points bigint)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
with matches as (
    select m.home_id uid,m.home_score own,m.away_score other,
           t.win_points winpoints,t.draw_points drawpoints
    from public.athlth_tournament_matches m
    join public.athlth_tournaments t on t.id=m.tournament_id
    where t.season_id=p_season and m.status='confirmed'
      and m.away_id is not null and m.phase<>'warmup'
          and (not t.competition_settings_applied
            or t.format not in ('league','groups')
            or t.status='completed'
            or not exists(
                select 1 from public.athlth_tournament_matches pending
                where pending.tournament_id=m.tournament_id
                  and pending.phase=m.phase
                  and pending.round_number=m.round_number
                  and pending.group_index is not distinct from m.group_index
                  and pending.away_id is not null
                  and pending.status<>'confirmed'))
    union all
    select m.away_id,m.away_score,m.home_score,
           t.win_points,t.draw_points
    from public.athlth_tournament_matches m
    join public.athlth_tournaments t on t.id=m.tournament_id
    where t.season_id=p_season and m.status='confirmed'
      and m.away_id is not null and m.phase<>'warmup'
          and (not t.competition_settings_applied
            or t.format not in ('league','groups')
            or t.status='completed'
            or not exists(
                select 1 from public.athlth_tournament_matches pending
                where pending.tournament_id=m.tournament_id
                  and pending.phase=m.phase
                  and pending.round_number=m.round_number
                  and pending.group_index is not distinct from m.group_index
                  and pending.away_id is not null
                  and pending.status<>'confirmed'))
)
select r.uid as user_id,
  coalesce(p.username::text,'Utøver') username,
  count(*)::bigint as matches,
  count(*) filter(where r.own>r.other)::bigint wins,
  sum(case when r.own>r.other then r.winpoints
           when r.own=r.other then r.drawpoints
           else 0 end)::bigint as season_points
from matches r
join public.profiles p on p.id=r.uid
join public.arena_club_seasons season on season.id=p_season
join public.community_group_members authorized
  on authorized.group_id=season.club_id and authorized.user_id=auth.uid()
group by r.uid,p.username
order by season_points desc,wins desc,matches desc,r.uid;
$function$
;
revoke all on function public.athlth_tournament_season_standings(uuid) from public,anon;
grant execute on function public.athlth_tournament_season_standings(uuid) to authenticated;