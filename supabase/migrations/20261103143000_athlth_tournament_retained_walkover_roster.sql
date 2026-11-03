-- Retained walkover competitors remain visible in completed league
-- tables as participants with losses. They cannot vote, chat or become ready.
-- Removing a player before first start still excludes them from the draw.
create or replace function public.athlth_tournament_forfeit_player(
 p_tournament uuid,p_player uuid
) returns integer language plpgsql security definer set search_path='' as $$
declare
 v_t public.athlth_tournaments%rowtype;
 v_actor uuid:=auth.uid();
 v_match record;
 v_count integer:=0;
begin
 if v_actor is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments where id=p_tournament for update;
 if not found or v_t.owner_id<>v_actor or
    v_t.status not in ('inviting','active') then
   raise exception 'Only an active organizer can remove a player';
 end if;
 if p_player=v_actor then raise exception 'Organizer cannot remove themselves'; end if;
 update public.athlth_tournament_entries
    set removed_at=now(),
       response=case when v_t.status='active' then 'accepted'
                     else 'declined' end,
       is_ready=false,ready_at=null
 where tournament_id=p_tournament and user_id=p_player
   and response in ('accepted','invited') and removed_at is null;
 if not found then raise exception 'Player not found or already removed'; end if;

 if v_t.status='inviting' then
    update public.athlth_tournament_entries
       set is_ready=false,ready_at=null where tournament_id=p_tournament;
 else
    for v_match in
        select id,home_id,away_id,phase,round_number
        from public.athlth_tournament_matches
        where tournament_id=p_tournament and status<>'confirmed'
          and (home_id=p_player or away_id=p_player)
        order by phase,round_number,slot_index
    loop
      if v_match.away_id is not null then
        update public.athlth_tournament_matches
           set status='confirmed',
               home_score=case when home_id=p_player then 0 else 1 end,
               away_score=case when away_id=p_player then 0 else 1 end,
               confirmed_by=v_actor,confirmed_at=now(),
               proposed_by=null,
               walkover_loser_id=p_player,
               walkover_reason='removed_by_organizer',
               evidence_note='Walkover: athlete removed by tournament organizer'
        where id=v_match.id;
        v_count:=v_count+1;
      end if;
    end loop;
    -- Recompute possible progression for each phase; confirmed results
    -- from before the removal are not touched.
    perform private.athlth_tournament_advance(p_tournament);
 end if;
 insert into public.athlth_tournament_audit(
   tournament_id,actor_id,event,info
 ) values(p_tournament,v_actor,'participant_forfeited',
    jsonb_build_object('player',p_player,'walkovers',v_count));
 return v_count;
end;
$$;

-- Administrator choice 2: ask a new athlete to replace a player.
-- If opted in, every other current athlete must explicitly approve.

revoke all on function public.athlth_tournament_forfeit_player(uuid,uuid)
 from public,anon;
grant execute on function public.athlth_tournament_forfeit_player(uuid,uuid)
 to authenticated;
