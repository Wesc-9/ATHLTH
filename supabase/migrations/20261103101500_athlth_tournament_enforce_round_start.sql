-- Competition dates must be enforceable server-side, not only a
-- decorative label on the iPhone.
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
    if v_match.scheduled_at is not null
       and clock_timestamp()<v_match.scheduled_at then
        raise exception 'This match is scheduled for a future round';
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
