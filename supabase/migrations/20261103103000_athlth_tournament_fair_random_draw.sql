-- Randomized, server-persisted draw. Fair cup byes and group placement
-- no longer privilege the tournament creator's fixed seed=1. Both the
-- official standings and playoff qualification use the same draw rank.
alter table public.athlth_tournament_entries
 add column if not exists draw_position integer;
create unique index if not exists athlth_tournament_unique_draw
 on public.athlth_tournament_entries(tournament_id,draw_position)
 where draw_position is not null;

create or replace function public.athlth_tournament_start(
    p_tournament uuid
) returns void language plpgsql security definer
set search_path='' as $$
declare
    v_actor uuid := auth.uid();
    v_t public.athlth_tournaments%rowtype;
    v_members uuid[];
    v_count integer;
    v_pending integer;
    v_groups integer;
    v_group integer;
    v_group_members uuid[];
    v_warmups integer;
    v_index integer;
begin
    if v_actor is null then raise exception 'Sign in required'; end if;
    select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
    if not found or v_t.owner_id<>v_actor then
        raise exception 'Only the organizer can start the competition';
    end if;
    if v_t.status<>'inviting' then
        raise exception 'Tournament is not awaiting invitations';
    end if;
    select count(*) into v_pending from public.athlth_tournament_entries
    where tournament_id=p_tournament and response='invited';
    if v_pending<>0 then
        raise exception 'Wait for every invited athlete to respond';
    end if;
    -- Fair, tamper-resistant draw. The organizer is NOT automatically
    -- assigned the first seed or any potential bye.
    select array_agg(user_id order by draw_key,user_id) into v_members
    from (
        select user_id, random() as draw_key
        from public.athlth_tournament_entries
        where tournament_id=p_tournament and response='accepted'
    ) shuffled;
    v_count := coalesce(array_length(v_members,1),0);
    if v_count<2 then raise exception 'At least two athletes must accept'; end if;
    for v_index in 1..v_count loop
        update public.athlth_tournament_entries
           set draw_position=v_index
         where tournament_id=p_tournament
           and user_id=v_members[v_index];
    end loop;

    if v_t.format='groups' and v_count<=v_t.group_size then
        raise exception 'Choose more athletes than one group, or use league';
    end if;
    select count(*) into v_warmups from public.athlth_tournament_practice
    where tournament_id=p_tournament;
    if v_warmups>0 then
        perform private.athlth_schedule_round_robin(
            p_tournament,v_members,'warmup',null,v_warmups
        );
    end if;
    if v_t.format='league' then
        perform private.athlth_schedule_round_robin(
            p_tournament,v_members,'league',null,null
        );
    elsif v_t.format='groups' then
        v_groups := ceil(v_count::numeric / v_t.group_size)::integer;
        if v_count<2*v_groups or
           v_t.qualifiers_per_group>floor(v_count::numeric/v_groups) then
            raise exception 'Group size or qualifiers would create an unfair one-person group';
        end if;
        for v_index in 1..v_count loop
            update public.athlth_tournament_entries
               set group_index=(v_index-1) % v_groups
             where tournament_id=p_tournament
               and user_id=v_members[v_index];
        end loop;
        for v_group in 0..(v_groups-1) loop
            select array_agg(user_id order by draw_position) into v_group_members
            from public.athlth_tournament_entries
            where tournament_id=p_tournament and response='accepted'
              and group_index=v_group;
            perform private.athlth_schedule_round_robin(
                p_tournament,v_group_members,'group',v_group,null
            );
        end loop;
    else
        perform private.athlth_schedule_knockout(
            p_tournament,v_members,'cup',1
        );
    end if;
    update public.athlth_tournaments
    set status='active',started_at=now() where id=p_tournament;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(p_tournament,v_actor,'started',
        jsonb_build_object('accepted',v_count,'warmups',v_warmups));
end;
$$;


create or replace function private.athlth_tournament_advance(p_tournament uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
    v_t public.athlth_tournaments%rowtype;
    v_phase text;
    v_round integer;
    v_winners uuid[];
    v_group integer;
    v_group_count integer;
    v_candidate record;
    v_qualified uuid[] := array[]::uuid[];
begin
    select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
    if not found or v_t.status <> 'active' then return; end if;

    if v_t.format='league' then
        if not exists(
            select 1 from public.athlth_tournament_matches
            where tournament_id=p_tournament and phase='league'
                and status<>'confirmed'
        ) then
            update public.athlth_tournaments
            set status='completed',completed_at=now()
            where id=p_tournament;
        end if;
        return;
    end if;

    if v_t.format='groups' and not exists(
        select 1 from public.athlth_tournament_matches
        where tournament_id=p_tournament and phase='playoff'
    ) then
        if exists(
            select 1 from public.athlth_tournament_matches
            where tournament_id=p_tournament and phase='group'
              and status<>'confirmed'
        ) then return; end if;
        select coalesce(max(group_index),-1)+1 into v_group_count
        from public.athlth_tournament_entries
        where tournament_id=p_tournament and response='accepted';
        for v_group in 0..v_group_count-1 loop
            for v_candidate in
                select e.user_id, e.seed,
                    coalesce(stats.points,0) as points,
                    coalesce(stats.diff,0) as diff,
                    coalesce(stats.scored,0) as scored
                from public.athlth_tournament_entries e
                cross join lateral (
                    select
                        sum(case
                            when m.home_score=m.away_score then v_t.draw_points
                            when (m.home_id=e.user_id and m.home_score>m.away_score)
                              or (m.away_id=e.user_id and m.away_score>m.home_score)
                            then v_t.win_points else 0 end) as points,
                        sum(case when m.home_id=e.user_id
                            then m.home_score-m.away_score
                            else m.away_score-m.home_score end) as diff,
                        sum(case when m.home_id=e.user_id
                            then m.home_score else m.away_score end) as scored
                    from public.athlth_tournament_matches m
                    where m.tournament_id=p_tournament and
                          m.phase='group' and m.group_index=v_group and
                          m.status='confirmed' and
                          (m.home_id=e.user_id or m.away_id=e.user_id)
                ) stats
                where e.tournament_id=p_tournament
                  and e.response='accepted' and e.group_index=v_group
                order by points desc,diff desc,scored desc,
                         coalesce(e.draw_position,e.seed)
                limit v_t.qualifiers_per_group
            loop
                v_qualified:=array_append(v_qualified,v_candidate.user_id);
            end loop;
        end loop;
        if array_length(v_qualified,1) < 2 then
            raise exception 'Not enough qualified athletes';
        end if;
        perform private.athlth_tournament_seed_knockout(
            p_tournament,'playoff',1,v_qualified
        );
        insert into public.athlth_tournament_audit(tournament_id,event,info)
        values(p_tournament,'playoff_created',
            jsonb_build_object('qualified',array_length(v_qualified,1)));
        return;
    end if;

    v_phase:=case when v_t.format='cup' then 'cup' else 'playoff' end;
    select max(round_number) into v_round
    from public.athlth_tournament_matches
    where tournament_id=p_tournament and phase=v_phase;
    if v_round is null or exists(
        select 1 from public.athlth_tournament_matches
        where tournament_id=p_tournament and phase=v_phase
          and round_number=v_round and status<>'confirmed'
    ) then return; end if;

    select array_agg(
        case when away_id is null then home_id
             when home_score>away_score then home_id
             else away_id end order by slot_index
    ) into v_winners from public.athlth_tournament_matches
    where tournament_id=p_tournament and phase=v_phase
      and round_number=v_round and status='confirmed';
    if array_length(v_winners,1) <= 1 then
        update public.athlth_tournaments
        set status='completed',completed_at=now()
        where id=p_tournament;
        insert into public.athlth_tournament_audit(tournament_id,event,info)
        values(p_tournament,'champion_confirmed',
            jsonb_build_object('champion',v_winners[1]));
    else
        perform private.athlth_tournament_seed_knockout(
            p_tournament,v_phase,v_round+1,v_winners
        );
        insert into public.athlth_tournament_audit(tournament_id,event,info)
        values(p_tournament,'round_advanced',
            jsonb_build_object('phase',v_phase,'next_round',v_round+1));
    end if;
end;
$$;

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
order by v.group_index nulls first,rank;
$$;

revoke all on function public.athlth_tournament_start(uuid)
 from public,anon;
grant execute on function public.athlth_tournament_start(uuid)
 to authenticated;
revoke all on function private.athlth_tournament_advance(uuid)
 from public,anon,authenticated;
revoke all on function public.athlth_tournament_standings(uuid,integer)
 from public,anon;
grant execute on function public.athlth_tournament_standings(uuid,integer)
 to authenticated;
