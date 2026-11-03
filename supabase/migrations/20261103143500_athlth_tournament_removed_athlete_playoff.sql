-- Removed athletes keep historical points in the league table,
-- but they cannot occupy a new playoff qualification slot.
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
                  and e.response='accepted' and e.removed_at is null
                  and e.group_index=v_group
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


revoke all on function private.athlth_tournament_advance(uuid)
 from public,anon,authenticated;
