-- Administrator choice 1: retain the former athlete's history and award
-- remaining unconfirmed fixtures to their opponent as audited walkovers.
alter table public.athlth_tournament_matches
 add column if not exists walkover_loser_id uuid references public.profiles(id),
 add column if not exists walkover_reason text;

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
    set removed_at=now(),response='declined',is_ready=false,ready_at=null
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
create or replace function private.athlth_tournament_apply_player_change(
 p_request uuid
) returns boolean language plpgsql security definer set search_path='' as $$
declare
 v_req public.athlth_tournament_player_change%rowtype;
 v_t public.athlth_tournaments%rowtype;
 v_old public.athlth_tournament_entries%rowtype;
 v_remaining integer;
 v_consents integer;
 v_max_seed integer;
begin
 select * into v_req from public.athlth_tournament_player_change
  where id=p_request for update;
 if not found or v_req.status<>'pending' or
    v_req.new_player_accepted is not true then return false; end if;
 select * into v_t from public.athlth_tournaments
  where id=v_req.tournament_id for update;
 if v_t.status not in ('inviting','active') then return false; end if;

 if v_req.requires_approval then
    select count(*) into v_remaining from public.athlth_tournament_entries
    where tournament_id=v_t.id and response='accepted'
      and removed_at is null and user_id<>v_req.old_player_id;
    select count(*) into v_consents
    from public.athlth_tournament_player_change_votes v
    join public.athlth_tournament_entries e
      on e.user_id=v.voter_id and e.tournament_id=v_t.id
    where v.request_id=p_request and v.approved
      and e.response='accepted' and e.removed_at is null
      and e.user_id<>v_req.old_player_id;
    if v_consents<>v_remaining then return false; end if;
 end if;
 select * into v_old from public.athlth_tournament_entries
   where tournament_id=v_t.id and user_id=v_req.old_player_id
   for update;
 if not found or v_old.removed_at is not null then return false; end if;
 if exists(
   select 1 from public.athlth_tournament_entries
   where tournament_id=v_t.id and user_id=v_req.new_player_id
 ) then raise exception 'Replacement is already an entrant'; end if;
 if exists(
   select 1 from public.athlth_tournament_matches
   where tournament_id=v_t.id and status='proposed'
     and (home_id=v_req.old_player_id or away_id=v_req.old_player_id)
 ) then raise exception 'Resolve outstanding proposed results before replacing'; end if;

 select coalesce(max(seed),0)+1 into v_max_seed
   from public.athlth_tournament_entries where tournament_id=v_t.id;
 update public.athlth_tournament_entries
    set response='declined', removed_at=now(),is_ready=false,
        ready_at=null,draw_position=null,replaced_by=v_req.new_player_id
 where tournament_id=v_t.id and user_id=v_req.old_player_id;
 insert into public.athlth_tournament_entries(
    tournament_id,user_id,seed,response,responded_at,
    group_index,draw_position,is_ready
 ) values(
    v_t.id,v_req.new_player_id,v_max_seed,'accepted',now(),
    v_old.group_index,v_old.draw_position,false
 );
 if v_t.status='active' then
    update public.athlth_tournament_matches
       set home_id=case when home_id=v_req.old_player_id
                 then v_req.new_player_id else home_id end,
           away_id=case when away_id=v_req.old_player_id
                 then v_req.new_player_id else away_id end
     where tournament_id=v_t.id and status in ('scheduled','disputed')
       and (home_id=v_req.old_player_id or away_id=v_req.old_player_id);
 else
    update public.athlth_tournament_entries
       set is_ready=false,ready_at=null where tournament_id=v_t.id;
 end if;
 update public.athlth_tournament_player_change
    set status='applied',applied_at=now() where id=p_request;
 insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
 values(v_t.id,v_req.initiated_by,'participant_replaced',
    jsonb_build_object('previous',v_req.old_player_id,
                       'replacement',v_req.new_player_id,
                       'requires_unanimous_approval',v_req.requires_approval));
 return true;
end;
$$;

create or replace function public.athlth_tournament_request_replacement(
 p_tournament uuid,p_old uuid,p_new uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_t public.athlth_tournaments%rowtype;
 v_request uuid;
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_t from public.athlth_tournaments where id=p_tournament for update;
 if not found or v_t.owner_id<>v_user or
    v_t.status not in ('inviting','active') then
    raise exception 'Organizer authorization required';
 end if;
 if p_old=v_user or p_old=p_new or p_new is null then
    raise exception 'Invalid replacement';
 end if;
 if not exists(select 1 from public.athlth_tournament_entries
     where tournament_id=p_tournament and user_id=p_old
       and response in ('accepted','invited') and removed_at is null)
    or exists(select 1 from public.athlth_tournament_entries
     where tournament_id=p_tournament and user_id=p_new)
    or not exists(select 1 from public.profiles where id=p_new) then
    raise exception 'Old or new player is not eligible';
 end if;
 if exists(select 1 from public.user_blocks b
     where (b.blocker_id=v_user and b.blocked_id=p_new)
        or (b.blocker_id=p_new and b.blocked_id=v_user)) then
    raise exception 'A blocked player cannot be invited';
 end if;
 insert into public.athlth_tournament_player_change(
    tournament_id,old_player_id,new_player_id,initiated_by,requires_approval
 ) values(p_tournament,p_old,p_new,v_user,v_t.approve_player_changes)
 returning id into v_request;
 if v_t.approve_player_changes then
    insert into public.athlth_tournament_player_change_votes(
      request_id,voter_id,approved
    ) values(v_request,v_user,true);
 end if;
 return v_request;
end;
$$;

create or replace function public.athlth_tournament_respond_replacement(
 p_request uuid,p_accept boolean
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_request public.athlth_tournament_player_change%rowtype;
 v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_request from public.athlth_tournament_player_change
    where id=p_request for update;
 if not found or v_request.new_player_id<>v_user or
    v_request.status<>'pending' then
    raise exception 'No pending replacement offer';
 end if;
 if not p_accept then
    update public.athlth_tournament_player_change
       set status='rejected' where id=p_request;
 else
    update public.athlth_tournament_player_change
       set new_player_accepted=true where id=p_request;
    perform private.athlth_tournament_apply_player_change(p_request);
 end if;
end;
$$;

create or replace function public.athlth_tournament_vote_replacement(
 p_request uuid,p_approve boolean
) returns void language plpgsql security definer set search_path='' as $$
declare
 v_request public.athlth_tournament_player_change%rowtype;
 v_user uuid:=auth.uid();
begin
 if v_user is null then raise exception 'Sign in required'; end if;
 select * into v_request from public.athlth_tournament_player_change
 where id=p_request for update;
 if not found or v_request.status<>'pending' or
    not v_request.requires_approval then
    raise exception 'Replacement vote not available';
 end if;
 if v_request.old_player_id=v_user or
    not private.athlth_tournament_is_accepted(v_request.tournament_id) then
    raise exception 'Not eligible to approve this roster change';
 end if;
 insert into public.athlth_tournament_player_change_votes(
    request_id,voter_id,approved
 ) values(p_request,v_user,p_approve)
 on conflict(request_id,voter_id) do update
   set approved=excluded.approved,voted_at=now();
 if not p_approve then
    update public.athlth_tournament_player_change
      set status='rejected' where id=p_request;
 else
    perform private.athlth_tournament_apply_player_change(p_request);
 end if;
end;
$$;

revoke all on function public.athlth_tournament_forfeit_player(uuid,uuid),
 public.athlth_tournament_request_replacement(uuid,uuid,uuid),
 public.athlth_tournament_respond_replacement(uuid,boolean),
 public.athlth_tournament_vote_replacement(uuid,boolean) from public,anon;
revoke all on function private.athlth_tournament_apply_player_change(uuid)
 from public,anon,authenticated;
grant execute on function public.athlth_tournament_forfeit_player(uuid,uuid),
 public.athlth_tournament_request_replacement(uuid,uuid,uuid),
 public.athlth_tournament_respond_replacement(uuid,boolean),
 public.athlth_tournament_vote_replacement(uuid,boolean) to authenticated;
