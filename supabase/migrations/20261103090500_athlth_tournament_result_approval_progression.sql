-- Opponent-approved reports; disputed reports never award points.
-- Any transition that might advance a bracket locks the parent tournament.
create or replace function private.athlth_progress_tournament(
    p_tournament uuid, p_phase text, p_round integer
) returns void
language plpgsql security definer set search_path='' as $$
declare
    v_t public.athlth_tournaments%rowtype;
    v_winners uuid[];
    v_next integer;
    v_unresolved integer;
begin
    select * into v_t from public.athlth_tournaments
     where id=p_tournament for update;
    if not found or v_t.status<>'active' or p_phase='warmup' then return; end if;
    if p_phase='league' then
        select count(*) into v_unresolved
        from public.athlth_tournament_matches
        where tournament_id=p_tournament and phase='league'
          and status<>'confirmed';
        if v_unresolved=0 then
            update public.athlth_tournaments
            set status='completed',completed_at=now()
            where id=p_tournament;
            insert into public.athlth_tournament_audit(
                tournament_id,event
            ) values(p_tournament,'completed');
        end if;
        return;
    end if;

    if p_phase='group' then
        select count(*) into v_unresolved
        from public.athlth_tournament_matches
        where tournament_id=p_tournament and phase='group'
          and status<>'confirmed';
        if v_unresolved>0 or exists(
           select 1 from public.athlth_tournament_matches
           where tournament_id=p_tournament and phase='playoff'
        ) then return; end if;
        -- Points, difference, total scored, wins and seed resolve standings.
        -- Group practice is entirely absent from this aggregation.
        with legs as (
            select m.group_index, m.home_id athlete,
              case when m.home_score>m.away_score then v_t.win_points
                   when m.home_score=m.away_score then v_t.draw_points
                   else 0 end as points,
              (m.home_score-m.away_score) as difference,
              m.home_score as scored,
              case when m.home_score>m.away_score then 1 else 0 end as wins
            from public.athlth_tournament_matches m
            where m.tournament_id=p_tournament
              and m.phase='group' and m.status='confirmed'
            union all
            select m.group_index,m.away_id,
              case when m.away_score>m.home_score then v_t.win_points
                   when m.away_score=m.home_score then v_t.draw_points
                   else 0 end,
              (m.away_score-m.home_score),m.away_score,
              case when m.away_score>m.home_score then 1 else 0 end
            from public.athlth_tournament_matches m
            where m.tournament_id=p_tournament
              and m.phase='group' and m.status='confirmed'
        ), scores as (
            select e.group_index,e.user_id,e.seed,
              coalesce(sum(l.points),0) points,
              coalesce(sum(l.difference),0) difference,
              coalesce(sum(l.scored),0) scored,
              coalesce(sum(l.wins),0) wins
            from public.athlth_tournament_entries e
            left join legs l on l.athlete=e.user_id
                and l.group_index=e.group_index
            where e.tournament_id=p_tournament and e.response='accepted'
            group by e.group_index,e.user_id,e.seed
        ), ranked as (
            select user_id,group_index,
              row_number() over (
                partition by group_index
                order by points desc,difference desc,scored desc,
                         wins desc,seed asc
              ) rank
            from scores
        ) select array_agg(user_id order by rank,group_index)
          into v_winners from ranked
         where rank<=v_t.qualifiers_per_group;
        if coalesce(array_length(v_winners,1),0)<2 then
            raise exception 'Group results cannot produce a playoff';
        end if;
        perform private.athlth_schedule_knockout(
            p_tournament,v_winners,'playoff',1
        );
        insert into public.athlth_tournament_audit(
            tournament_id,event,info
        ) values(p_tournament,'playoffs_created',
            jsonb_build_object('qualified',array_length(v_winners,1)));
        return;
    end if;

    if p_phase in ('cup','playoff') then
        -- This method runs once after each independently confirmed report.
        -- A bye is a free advancement, never a win or a point.
        select count(*) into v_unresolved
        from public.athlth_tournament_matches
        where tournament_id=p_tournament and phase=p_phase
          and round_number=p_round
          and away_id is not null and status<>'confirmed';
        if v_unresolved>0 then return; end if;
        if exists(
            select 1 from public.athlth_tournament_matches
            where tournament_id=p_tournament and phase=p_phase
              and round_number=p_round+1
        ) then return; end if;
        select array_agg(
          case when away_id is null or home_score>away_score
               then home_id else away_id end order by slot_index
        ) into v_winners
        from public.athlth_tournament_matches
        where tournament_id=p_tournament and phase=p_phase
          and round_number=p_round;
        v_next := coalesce(array_length(v_winners,1),0);
        if v_next=1 then
            update public.athlth_tournaments
               set status='completed',completed_at=now()
             where id=p_tournament;
            insert into public.athlth_tournament_audit(
                tournament_id,event,info
            ) values(p_tournament,'completed',
                jsonb_build_object('winner_id',v_winners[1]));
        elsif v_next>1 then
            perform private.athlth_schedule_knockout(
                p_tournament,v_winners,p_phase,p_round+1
            );
            insert into public.athlth_tournament_audit(
                tournament_id,event,info
            ) values(p_tournament,'next_round_created',
                jsonb_build_object('round',p_round+1,'participants',v_next));
        end if;
    end if;
end;
$$;

create or replace function public.athlth_tournament_propose_result(
    p_match uuid, p_home_score numeric, p_away_score numeric,
    p_evidence_note text default ''
) returns void
language plpgsql security definer set search_path='' as $$
declare
    v_user uuid := auth.uid();
    v_match public.athlth_tournament_matches%rowtype;
    v_status text;
begin
    if v_user is null then raise exception 'Sign in required'; end if;
    if p_home_score is null or p_away_score is null or
       p_home_score<0 or p_away_score<0 or
       p_home_score>1000000 or p_away_score>1000000 or
       length(coalesce(p_evidence_note,''))>1000 then
        raise exception 'Invalid scores or evidence';
    end if;
    select tournament_id into v_match.tournament_id
    from public.athlth_tournament_matches where id=p_match;
    if v_match.tournament_id is null then
        raise exception 'Match not found';
    end if;
    select status into v_status from public.athlth_tournaments
     where id=v_match.tournament_id for update;
    if v_status<>'active' then raise exception 'Tournament not active'; end if;
    select * into v_match from public.athlth_tournament_matches
    where id=p_match for update;
    if v_match.away_id is null or
       v_user not in (v_match.home_id,v_match.away_id) then
        raise exception 'Only competing athletes may report a match';
    end if;
    if v_match.status not in ('scheduled','disputed') then
        raise exception 'This result is already proposed or final';
    end if;
    if v_match.phase in ('cup','playoff') and
       p_home_score=p_away_score then
        raise exception 'Knockout requires a winner; resolve a tie first';
    end if;
    update public.athlth_tournament_matches
       set home_score=p_home_score, away_score=p_away_score,
           status='proposed', proposed_by=v_user,
           confirmed_by=null,confirmed_at=null,
           evidence_note=coalesce(p_evidence_note,'')
    where id=p_match;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(v_match.tournament_id,v_user,'result_proposed',
       jsonb_build_object('match_id',p_match));
end;
$$;

create or replace function public.athlth_tournament_review_result(
    p_match uuid, p_approve boolean
) returns void
language plpgsql security definer set search_path='' as $$
declare
    v_user uuid := auth.uid();
    v_match public.athlth_tournament_matches%rowtype;
    v_state text;
begin
    if v_user is null then raise exception 'Sign in required'; end if;
    select tournament_id into v_match.tournament_id
    from public.athlth_tournament_matches where id=p_match;
    if v_match.tournament_id is null then
        raise exception 'Match not found';
    end if;
    select status into v_state from public.athlth_tournaments
      where id=v_match.tournament_id for update;
    if v_state<>'active' then
        raise exception 'Tournament not active';
    end if;
    select * into v_match from public.athlth_tournament_matches
      where id=p_match for update;
    if v_match.status<>'proposed' or
       v_user=v_match.proposed_by or
       v_user not in (v_match.home_id,v_match.away_id) then
        raise exception 'Only the opposing athlete may confirm or dispute';
    end if;
    update public.athlth_tournament_matches
       set status=case when p_approve then 'confirmed' else 'disputed' end,
           confirmed_by=case when p_approve then v_user else null end,
           confirmed_at=case when p_approve then now() else null end
     where id=p_match;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(v_match.tournament_id,v_user,
       case when p_approve then 'result_confirmed' else 'result_disputed' end,
       jsonb_build_object('match_id',p_match));
    if p_approve then
        perform private.athlth_progress_tournament(
           v_match.tournament_id,v_match.phase,v_match.round_number
        );
    end if;
end;
$$;

revoke all on function private.athlth_progress_tournament(uuid,text,integer)
 from public,anon,authenticated;
revoke all on function public.athlth_tournament_propose_result(
 uuid,numeric,numeric,text) from public,anon;
revoke all on function public.athlth_tournament_review_result(uuid,boolean)
 from public,anon;
grant execute on function public.athlth_tournament_propose_result(
 uuid,numeric,numeric,text) to authenticated;
grant execute on function public.athlth_tournament_review_result(uuid,boolean)
 to authenticated;
