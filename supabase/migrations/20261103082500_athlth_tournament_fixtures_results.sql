-- Match scheduling and opponent-confirmed outcomes for ATHLTH tournaments.
-- Never include warmup fixtures in points, qualification or elimination.
create or replace function private.athlth_tournament_seed_knockout(
    p_tournament uuid, p_phase text, p_round integer, p_players uuid[]
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
    v_count integer := coalesce(array_length(p_players,1),0);
    v_capacity integer := 2;
    v_byes integer;
    v_index integer := 1;
    v_match integer;
    v_away uuid;
begin
    if p_phase not in ('cup','playoff') or v_count < 2 or v_count > 128 then
        raise exception 'Invalid knockout schedule';
    end if;
    while v_capacity < v_count loop v_capacity:=v_capacity*2; end loop;
    v_byes:=v_capacity-v_count;
    for v_match in 1..v_capacity/2 loop
        if v_match <= v_byes then
            v_away:=null;
        else
            v_away:=p_players[v_index+1];
        end if;
        insert into public.athlth_tournament_matches(
            tournament_id,phase,round_number,slot_index,
            home_id,away_id,status
        ) values(
            p_tournament,p_phase,p_round,v_match,
            p_players[v_index],v_away,
            case when v_away is null then 'confirmed' else 'scheduled' end
        );
        v_index:=v_index+case when v_away is null then 1 else 2 end;
    end loop;
end;
$$;
revoke all on function private.athlth_tournament_seed_knockout(
 uuid,text,integer,uuid[]) from public,anon,authenticated;

create or replace function public.athlth_tournament_start(p_tournament uuid)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
    v_owner uuid := auth.uid();
    v_t public.athlth_tournaments%rowtype;
    v_players uuid[];
    v_arr uuid[];
    v_group integer;
    v_group_count integer;
    v_count integer;
    v_size integer;
    v_round integer;
    v_pair integer;
    v_slot integer;
    v_k integer;
    v_last uuid;
    v_left uuid;
    v_right uuid;
    v_phase text;
    v_practice record;
    v_player1 integer;
    v_player2 integer;
begin
    if v_owner is null then raise exception 'Sign in required'; end if;
    select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
    if not found or v_t.owner_id <> v_owner or v_t.status <> 'inviting' then
        raise exception 'Only the organizer can start a pending tournament';
    end if;
    if exists(
        select 1 from public.athlth_tournament_entries
        where tournament_id=p_tournament and response='invited'
    ) then
        raise exception 'Waiting for invited athletes to respond';
    end if;
    select array_agg(user_id order by seed) into v_players
    from public.athlth_tournament_entries
    where tournament_id=p_tournament and response='accepted';
    v_count:=coalesce(array_length(v_players,1),0);
    if v_count < 2 then
        raise exception 'At least two accepted athletes are required';
    end if;
    v_group_count:=case when v_t.format='groups'
        then ceil(v_count::numeric/v_t.group_size)::integer else 1 end;

    update public.athlth_tournament_entries e
    set group_index = case when v_t.format='groups' then
        (positions.rn - 1) % v_group_count else null end
    from (
        select user_id,
           row_number() over(order by seed)::integer rn
        from public.athlth_tournament_entries
        where tournament_id=p_tournament and response='accepted'
    ) positions
    where e.tournament_id=p_tournament and e.user_id=positions.user_id;

    -- Warmup has no score or bracket semantics, and is stored separately.
    for v_practice in
        select ordinal from public.athlth_tournament_practice
        where tournament_id=p_tournament order by ordinal
    loop
        for v_pair in 1..(v_count/2) loop
            v_player1:=((v_pair*2-2+v_practice.ordinal-1) % v_count)+1;
            v_player2:=((v_pair*2-1+v_practice.ordinal-1) % v_count)+1;
            insert into public.athlth_tournament_matches(
                tournament_id,phase,round_number,slot_index,home_id,away_id
            ) values(
                p_tournament,'warmup',v_practice.ordinal,v_pair,
                v_players[v_player1],v_players[v_player2]
            );
        end loop;
    end loop;

    if v_t.format = 'cup' then
        perform private.athlth_tournament_seed_knockout(
            p_tournament,'cup',1,v_players
        );
    else
        v_phase:=case when v_t.format='groups' then 'group' else 'league' end;
        for v_group in 0..v_group_count-1 loop
            if v_t.format='groups' then
                select array_agg(user_id order by seed) into v_arr
                from public.athlth_tournament_entries
                where tournament_id=p_tournament and response='accepted'
                    and group_index=v_group;
            else
                v_arr:=v_players;
            end if;
            if coalesce(array_length(v_arr,1),0) < 2 then continue; end if;
            if array_length(v_arr,1) % 2=1 then
                v_arr:=array_append(v_arr,null::uuid);
            end if;
            v_size:=array_length(v_arr,1);
            for v_round in 1..v_size-1 loop
                v_slot:=0;
                for v_pair in 1..v_size/2 loop
                    v_left:=v_arr[v_pair];
                    v_right:=v_arr[v_size-v_pair+1];
                    if v_left is not null and v_right is not null then
                        v_slot:=v_slot+1;
                        insert into public.athlth_tournament_matches(
                            tournament_id,phase,round_number,group_index,
                            slot_index,home_id,away_id
                        ) values(
                            p_tournament,v_phase,v_round,
                            case when v_phase='group' then v_group else null end,
                            v_slot,
                            case when (v_round+v_pair)%2=0 then v_right else v_left end,
                            case when (v_round+v_pair)%2=0 then v_left else v_right end
                        );
                    end if;
                end loop;
                v_last:=v_arr[v_size];
                for v_k in reverse v_size..3 loop
                    v_arr[v_k]:=v_arr[v_k-1];
                end loop;
                v_arr[2]:=v_last;
            end loop;
        end loop;
    end if;

    update public.athlth_tournaments
    set status='active',started_at=now()
    where id=p_tournament;
    insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
    values(p_tournament,v_owner,'started');
end;
$$;
revoke all on function public.athlth_tournament_start(uuid) from public,anon;
grant execute on function public.athlth_tournament_start(uuid) to authenticated;

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
                order by points desc,diff desc,scored desc,e.seed
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

create or replace function public.athlth_tournament_propose_result(
    p_match uuid,p_home_score numeric,p_away_score numeric,p_evidence text
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_match public.athlth_tournament_matches%rowtype;
    v_t_status text;
begin
    if v_user is null then raise exception 'Sign in required'; end if;
    select * into v_match from public.athlth_tournament_matches
    where id=p_match for update;
    if not found or v_user not in (v_match.home_id,v_match.away_id) or
       v_match.away_id is null or
       v_match.status not in ('scheduled','disputed') then
        raise exception 'Not eligible to propose a result';
    end if;
    select status into v_t_status from public.athlth_tournaments
    where id=v_match.tournament_id for update;
    if v_t_status <> 'active' or not exists(
        select 1 from public.athlth_tournament_entries e
        where e.tournament_id=v_match.tournament_id
        and e.user_id=v_user and e.response='accepted'
    ) then raise exception 'Tournament is not active for this athlete'; end if;
    if p_home_score is null or p_away_score is null or
       p_home_score < 0 or p_away_score < 0 or
       p_home_score > 100000000 or p_away_score > 100000000 or
       (v_match.phase in ('cup','playoff') and p_home_score=p_away_score) or
       length(btrim(coalesce(p_evidence,''))) > 400 then
        raise exception 'Invalid match score or evidence';
    end if;
    update public.athlth_tournament_matches
       set home_score=p_home_score,away_score=p_away_score,
           status='proposed',proposed_by=v_user,
           confirmed_by=null,confirmed_at=null,
           evidence_note=btrim(coalesce(p_evidence,''))
     where id=p_match;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(
        v_match.tournament_id,v_user,'result_proposed',
        jsonb_build_object('match',p_match)
    );
end;
$$;
revoke all on function public.athlth_tournament_propose_result(
 uuid,numeric,numeric,text) from public,anon;
grant execute on function public.athlth_tournament_propose_result(
 uuid,numeric,numeric,text) to authenticated;

create or replace function public.athlth_tournament_confirm_result(
    p_match uuid,p_confirm boolean
) returns void
language plpgsql security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_match public.athlth_tournament_matches%rowtype;
    v_status text;
begin
    if v_user is null then raise exception 'Sign in required'; end if;
    select * into v_match from public.athlth_tournament_matches
    where id=p_match for update;
    if not found or v_match.status<>'proposed' or
       v_match.proposed_by=v_user or
       v_user not in (v_match.home_id,v_match.away_id) then
        raise exception 'Independent opponent confirmation required';
    end if;
    select status into v_status from public.athlth_tournaments
    where id=v_match.tournament_id for update;
    if v_status <> 'active' then raise exception 'Tournament not active'; end if;
    update public.athlth_tournament_matches
       set status=case when p_confirm then 'confirmed' else 'disputed' end,
           confirmed_by=case when p_confirm then v_user else null end,
           confirmed_at=case when p_confirm then now() else null end
     where id=p_match;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(
        v_match.tournament_id,v_user,
        case when p_confirm then 'result_approved' else 'result_disputed' end,
        jsonb_build_object('match',p_match)
    );
    if p_confirm and v_match.phase<>'warmup' then
        perform private.athlth_tournament_advance(v_match.tournament_id);
    end if;
end;
$$;
revoke all on function public.athlth_tournament_confirm_result(
 uuid,boolean) from public,anon;
grant execute on function public.athlth_tournament_confirm_result(
 uuid,boolean) to authenticated;
