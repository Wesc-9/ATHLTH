-- Aggregate only server-confirmed official tournament matches into club season
-- standings. A warmup is intentionally absent from every points expression.
-- Invoker rights and table RLS prevent reading inaccessible seasons.
create or replace function public.athlth_tournament_season_scores(p_season uuid)
returns table(user_id uuid, points numeric, competitions bigint)
language sql stable security invoker
set search_path = ''
as $$
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
          and (m.home_id=e.user_id or m.away_id=e.user_id)
    ) scoring
    where t.season_id=p_season
      and t.status='completed'
      and auth.uid() is not null
      and exists(
          select 1 from public.community_group_members member
          where member.group_id=s.club_id and member.user_id=auth.uid()
      )
    group by e.user_id
    order by points desc,e.user_id;
$$;
revoke all on function public.athlth_tournament_season_scores(uuid)
 from public,anon;
grant execute on function public.athlth_tournament_season_scores(uuid)
 to authenticated;
