-- Replacement safety: respect recipient consent and give a substituted
-- athlete a fresh exercise window without rewriting completed matches.
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
    -- Only unfinished games are transferred. Restore a fresh proof window
    -- to the replacement; a displaced athlete's old self-reports cannot be
    -- treated as the replacement's workout.
    delete from public.athlth_tournament_exercise_completions c
     using public.athlth_tournament_match_exercises e,
           public.athlth_tournament_matches m
     where c.match_exercise_id=e.id and e.match_id=m.id
       and m.tournament_id=v_t.id and m.status in ('scheduled','disputed')
       and (m.home_id=v_req.old_player_id or m.away_id=v_req.old_player_id)
       and c.user_id=v_req.old_player_id;
    update public.athlth_tournament_match_exercises e
       set state='pending',winner_id=null,resolved_at=null
      from public.athlth_tournament_matches m
      where e.match_id=m.id
        and m.tournament_id=v_t.id and m.status in ('scheduled','disputed')
        and (m.home_id=v_req.old_player_id or m.away_id=v_req.old_player_id);
    update public.athlth_tournament_matches
       set home_id=case when home_id=v_req.old_player_id
                 then v_req.new_player_id else home_id end,
           away_id=case when away_id=v_req.old_player_id
                 then v_req.new_player_id else away_id end,
           status='scheduled',home_score=null,away_score=null,
           proposed_by=null,confirmed_by=null,confirmed_at=null,
           evidence_note='',
           deadline_at=greatest(coalesce(deadline_at,now()),
                                now()+interval '7 days')
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
 -- Honor the replacement's invitation settings just like the
 -- original tournament invitation, rather than bypassing privacy.
 if exists(
   select 1 from public.profile_social_settings settings
   where settings.user_id=p_new
     and (
       settings.allow_challenge_invites='nobody'
       or (settings.allow_challenge_invites='friends'
            and not exists(
              select 1 from public.profile_follows f
              join public.profile_follows b
                on b.follower_id=p_new and b.following_id=v_user
              where f.follower_id=v_user and f.following_id=p_new
            )
            and not (v_t.club_id is not null and exists(
              select 1 from public.community_group_members cm
              where cm.group_id=v_t.club_id and cm.user_id=p_new
            )))
       or (settings.allow_challenge_invites='everyone'
            and settings.discoverable is false)
     )
 ) then raise exception 'Replacement does not accept these invitations'; end if;

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


revoke all on function private.athlth_tournament_apply_player_change(uuid)
 from public,anon,authenticated;
revoke all on function public.athlth_tournament_request_replacement(uuid,uuid,uuid)
 from public,anon;
grant execute on function public.athlth_tournament_request_replacement(uuid,uuid,uuid)
 to authenticated;
