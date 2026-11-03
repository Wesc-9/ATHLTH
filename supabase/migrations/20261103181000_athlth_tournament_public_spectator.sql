-- Public spectator access is opt-in and strictly read-only. It reveals
-- usernames, approved scores, table and bracket; never contact details,
-- workout evidence, private invitations, internal votes or lobby chat.
create or replace function public.athlth_tournament_public_discover()
returns table(id uuid,title text,format text,status text,participant_count bigint)
language sql stable security definer set search_path='' as $$
 select t.id,t.title,t.format,t.status,
   (select count(*) from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.response='accepted')::bigint
 from public.athlth_tournaments t
 where auth.uid() is not null
   and t.public_results is true
   and t.status in ('active','completed')
 order by t.created_at desc,t.id
 limit 50;
$$;

create or replace function public.athlth_tournament_public_results(
 p_tournament uuid
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_matches jsonb;
 v_table jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments
 where id=p_tournament and public_results is true
   and status in ('active','completed');
 if not found then
    raise exception 'Tournament results are private or unavailable';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'phase',m.phase,'round',m.round_number,'group',m.group_index,
   'slot',m.slot_index,'status',m.status,
   'home',coalesce(home.username,'Utøver'),
   'away',coalesce(away.username,'Frirunde'),
   'home_score',case when m.status='confirmed' then m.home_score end,
   'away_score',case when m.status='confirmed' then m.away_score end
 ) order by m.phase,m.round_number,m.slot_index), '[]'::jsonb)
 into v_matches
 from (
   select * from public.athlth_tournament_matches
   where tournament_id=p_tournament
     and phase in ('league','group','cup','playoff')
   order by round_number,slot_index
   limit 500
 ) m
 join public.profiles home on home.id=m.home_id
 left join public.profiles away on away.id=m.away_id;

 with legs as (
    select m.home_id user_id,m.group_index,
       m.home_score own,m.away_score other
    from public.athlth_tournament_matches m
    where m.tournament_id=p_tournament and m.status='confirmed'
      and m.phase in ('league','group')
    union all
    select m.away_id,m.group_index,m.away_score,m.home_score
    from public.athlth_tournament_matches m
    where m.tournament_id=p_tournament and m.status='confirmed'
      and m.phase in ('league','group')
 ), totals as (
    select e.user_id,e.group_index,e.draw_position,
      coalesce(sum(case
        when l.own>l.other then v_t.win_points
        when l.own=l.other then v_t.draw_points
        else 0 end),0) points,
      coalesce(sum(l.own-l.other),0) difference,
      count(l.own) played,
      count(*) filter(where l.own>l.other) wins
    from public.athlth_tournament_entries e
    left join legs l on l.user_id=e.user_id
    where e.tournament_id=p_tournament and e.response='accepted'
    group by e.user_id,e.group_index,e.draw_position
 ), ranked as (
    select t.*,
       row_number() over(partition by t.group_index
       order by t.points desc,t.difference desc,t.wins desc,
                t.draw_position asc,t.user_id) as rank
    from totals t
 )
 select coalesce(jsonb_agg(jsonb_build_object(
     'username',coalesce(p.username,'Utøver'),
     'group',r.group_index,'rank',r.rank,
     'points',r.points,'difference',r.difference,
     'played',r.played,'wins',r.wins
 ) order by r.group_index nulls first,r.rank), '[]'::jsonb)
 into v_table
 from ranked r join public.profiles p on p.id=r.user_id;

 return jsonb_build_object(
   'id',v_t.id,'title',v_t.title,'format',v_t.format,
   'status',v_t.status,'standings',v_table,'matches',v_matches
 );
end;
$$;

revoke all on function public.athlth_tournament_public_discover(),
 public.athlth_tournament_public_results(uuid) from public,anon;
grant execute on function public.athlth_tournament_public_discover(),
 public.athlth_tournament_public_results(uuid) to authenticated;
