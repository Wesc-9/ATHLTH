-- Read-only league standings. Only independently confirmed official
-- league/group matches count; warmup rounds and unconfirmed reports do not.
-- SECURITY INVOKER means tournament and membership RLS remains effective.
create or replace function public.athlth_tournament_standings(
    p_tournament uuid, p_group integer default null
) returns table(
    user_id uuid, username text, group_index integer,
    played bigint, wins bigint, draws bigint, losses bigint,
    scored numeric, conceded numeric, points bigint, rank bigint
)
language sql stable security invoker set search_path='' as $$
with entrants as (
    select e.user_id, e.group_index,
      coalesce(p.username::text,'Utøver') as username
    from public.athlth_tournament_entries e
    left join public.profiles p on p.id=e.user_id
    where e.tournament_id=p_tournament
      and e.response='accepted'
      and (p_group is null or e.group_index=p_group)
), scores as (
    select e.user_id,e.username,e.group_index,
      m.id match_id,
      case when m.home_id=e.user_id then m.home_score
           else m.away_score end as own_score,
      case when m.home_id=e.user_id then m.away_score
           else m.home_score end as other_score
    from entrants e
    left join public.athlth_tournament_matches m
      on m.tournament_id=p_tournament
      and m.status='confirmed'
      and m.phase in ('league','group')
      and (m.home_id=e.user_id or m.away_id=e.user_id)
), totals as (
    select s.user_id,s.username,s.group_index,
      count(s.match_id)::bigint played,
      count(*) filter(
        where s.match_id is not null
        and s.own_score > s.other_score
      )::bigint wins,
      count(*) filter(
        where s.match_id is not null
        and s.own_score = s.other_score
      )::bigint draws,
      count(*) filter(
        where s.match_id is not null
        and s.own_score < s.other_score
      )::bigint losses,
      coalesce(sum(s.own_score),0)::numeric scored,
      coalesce(sum(s.other_score),0)::numeric conceded,
      (count(*) filter(
         where s.match_id is not null
         and s.own_score > s.other_score
       ) * coalesce(t.win_points,3) +
       count(*) filter(
         where s.match_id is not null
         and s.own_score = s.other_score
       ) * coalesce(t.draw_points,1))::bigint points
    from scores s
    left join public.athlth_tournaments t on t.id=p_tournament
    group by s.user_id,s.username,s.group_index,t.win_points,t.draw_points
)
select v.user_id,v.username,v.group_index,
       v.played,v.wins,v.draws,v.losses,v.scored,v.conceded,v.points,
       row_number() over(partition by v.group_index
          order by v.points desc,(v.scored-v.conceded) desc,
                   v.scored desc,v.wins desc,v.username asc,v.user_id
       ) as rank
from totals v
order by v.group_index nulls first,rank;
$$;
revoke all on function public.athlth_tournament_standings(uuid,integer)
 from anon, public;
grant execute on function public.athlth_tournament_standings(uuid,integer)
 to authenticated;

-- Season standings are a view of approved official matches across the
-- linked club tournaments. Cup winners receive the same match-win points;
-- warmups are explicitly excluded. No client-supplied totals are trusted.
create or replace function public.athlth_tournament_season_standings(
    p_season uuid
) returns table(user_id uuid, username text,
    matches bigint, wins bigint, season_points bigint)
language sql stable security invoker set search_path='' as $$
with matches as (
    select m.home_id uid,m.home_score own,m.away_score other,
           t.win_points winpoints,t.draw_points drawpoints
    from public.athlth_tournament_matches m
    join public.athlth_tournaments t on t.id=m.tournament_id
    where t.season_id=p_season and m.status='confirmed'
      and m.away_id is not null and m.phase<>'warmup'
    union all
    select m.away_id,m.away_score,m.home_score,
           t.win_points,t.draw_points
    from public.athlth_tournament_matches m
    join public.athlth_tournaments t on t.id=m.tournament_id
    where t.season_id=p_season and m.status='confirmed'
      and m.away_id is not null and m.phase<>'warmup'
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
group by r.uid,p.username
order by season_points desc,wins desc,matches desc,r.uid;
$$;
revoke all on function public.athlth_tournament_season_standings(uuid)
 from anon, public;
grant execute on function public.athlth_tournament_season_standings(uuid)
 to authenticated;
