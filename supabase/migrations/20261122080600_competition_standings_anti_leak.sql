CREATE OR REPLACE FUNCTION public.athlth_tournament_standings(p_tournament uuid, p_group integer DEFAULT NULL::integer)
 RETURNS TABLE(user_id uuid, username text, group_index integer, played bigint, wins bigint, draws bigint, losses bigint, scored numeric, conceded numeric, points bigint, rank bigint)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
with entrants as (
    select e.user_id, e.group_index,
      coalesce(e.draw_position,e.seed) as draw_position,
      coalesce(p.username::text,'Utøver') as username
    from public.athlth_tournament_entries e
    left join public.profiles p on p.id=e.user_id
    where e.tournament_id=p_tournament
      and e.response='accepted'
      and (p_group is null or e.group_index=p_group)
), scores as (
    select e.user_id,e.username,e.group_index,e.draw_position,
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
      and (
        not exists(select 1 from public.athlth_tournaments t
           where t.id=p_tournament and t.competition_settings_applied
             and t.format in ('league','groups') and t.status<>'completed')
        or not exists(select 1 from public.athlth_tournament_matches unresolved
           where unresolved.tournament_id=m.tournament_id
             and unresolved.phase=m.phase
             and unresolved.round_number=m.round_number
             and unresolved.group_index is not distinct from m.group_index
             and unresolved.away_id is not null
             and unresolved.status<>'confirmed')
      )
      and (m.home_id=e.user_id or m.away_id=e.user_id)
), totals as (
    select s.user_id,s.username,s.group_index,s.draw_position,
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
    group by s.user_id,s.username,s.group_index,s.draw_position,
             t.win_points,t.draw_points
)
select v.user_id,v.username,v.group_index,
       v.played,v.wins,v.draws,v.losses,v.scored,v.conceded,v.points,
       row_number() over(partition by v.group_index
          order by v.points desc,(v.scored-v.conceded) desc,
                   v.scored desc,v.wins desc,v.draw_position asc,v.user_id
       ) as rank
from totals v
where auth.uid() is not null
  and private.athlth_tournament_can_view(p_tournament)
order by v.group_index nulls first,rank;
$function$
;
revoke all on function public.athlth_tournament_standings(uuid,integer) from public,anon;
grant execute on function public.athlth_tournament_standings(uuid,integer) to authenticated;