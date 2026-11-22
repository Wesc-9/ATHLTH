create or replace function private.athlth_competition_activate_invite(
 p_tournament uuid,p_nominee uuid,p_actor uuid
) returns void language plpgsql security definer set search_path='' as $fn$
declare v_seed integer;
begin
 if exists(select 1 from public.athlth_tournament_entries
           where tournament_id=p_tournament and user_id=p_nominee) then
    raise exception 'Athlete already has an invitation';
 end if;
 select coalesce(max(seed),0)+1 into v_seed
 from public.athlth_tournament_entries where tournament_id=p_tournament;
 if v_seed>128 then raise exception 'Tournament is full'; end if;
 insert into public.athlth_tournament_entries(
   tournament_id,user_id,seed,response
 ) values(p_tournament,p_nominee,v_seed,'invited');
 insert into public.athlth_tournament_audit(
   tournament_id,actor_id,event,info
 ) values(p_tournament,p_actor,'extra_invitation_sent',
   jsonb_build_object('nominee',p_nominee));
end;
$fn$;
create or replace function public.athlth_tournament_propose_invite(
 p_tournament uuid,p_nominee uuid
) returns uuid language plpgsql security definer set search_path='' as $fn$
declare v_actor uuid:=auth.uid(); v_t public.athlth_tournaments%rowtype;
 v_request uuid; v_direct boolean;
begin
 if v_actor is null or p_nominee is null or p_nominee=v_actor
 then raise exception 'Invalid invite'; end if;
 select * into v_t from public.athlth_tournaments
 where id=p_tournament for update;
 if not found or v_t.status<>'inviting' or v_t.rules_frozen_at is not null
 then raise exception 'Competition invitations are closed'; end if;
 if v_actor<>v_t.owner_id and not (
   v_t.invitation_permission='participants'
   and exists(select 1 from public.athlth_tournament_entries e
       where e.tournament_id=p_tournament and e.user_id=v_actor
         and e.response='accepted' and e.removed_at is null)
 ) then raise exception 'You cannot invite people to this tournament'; end if;
 if not exists(select 1 from public.profiles where id=p_nominee)
   or exists(select 1 from public.athlth_tournament_entries
       where tournament_id=p_tournament and user_id=p_nominee)
 then raise exception 'Invalid or already invited athlete'; end if;
 if exists(select 1 from public.user_blocks b where
   (b.blocker_id=v_actor and b.blocked_id=p_nominee)
   or (b.blocker_id=p_nominee and b.blocked_id=v_actor))
   or coalesce((select s.allow_challenge_invites
      from public.profile_social_settings s where s.user_id=p_nominee),
      'friends')='nobody'
 then raise exception 'The athlete does not accept invitations'; end if;
 if not exists(select 1 from public.profile_follows f
   join public.profile_follows rev on rev.follower_id=p_nominee
      and rev.following_id=v_actor
   where f.follower_id=v_actor and f.following_id=p_nominee)
   and not (v_t.club_id is not null and exists(
     select 1 from public.community_group_members m
     where m.group_id=v_t.club_id and m.user_id=p_nominee))
   and not (
     coalesce((select s.allow_challenge_invites
       from public.profile_social_settings s
       where s.user_id=p_nominee),'friends')='everyone'
     and coalesce((select s.discoverable from public.profile_social_settings s
       where s.user_id=p_nominee),false)
   )
 then raise exception 'Athlete invitation privacy prevents this invite'; end if;
 v_direct:=v_t.join_approval='open' or
   (v_t.join_approval='admin' and v_actor=v_t.owner_id);
 insert into public.athlth_tournament_invite_requests(
   tournament_id,nominee_id,proposer_id,state,resolved_at
 ) values(p_tournament,p_nominee,v_actor,
          case when v_direct then 'approved' else 'pending' end,
          case when v_direct then now() else null end)
 returning id into v_request;
 if v_direct then
   perform private.athlth_competition_activate_invite(
     p_tournament,p_nominee,v_actor);
 end if;
 return v_request;
end;
$fn$;
create or replace function public.athlth_tournament_review_invite(
 p_request uuid,p_approved boolean
) returns boolean language plpgsql security definer set search_path='' as $fn$
declare v_actor uuid:=auth.uid(); v_request public.athlth_tournament_invite_requests%rowtype;
 v_t public.athlth_tournaments%rowtype; v_expected int; v_given int;
begin
 if v_actor is null or p_approved is null then
   raise exception 'Sign in and choose a decision'; end if;
 select * into v_request from public.athlth_tournament_invite_requests
 where id=p_request for update;
 if not found or v_request.state<>'pending' then
   raise exception 'Invitation request is already closed'; end if;
 select * into v_t from public.athlth_tournaments
 where id=v_request.tournament_id for update;
 if not found or v_t.status<>'inviting' or v_t.rules_frozen_at is not null
 then raise exception 'Invitations are closed'; end if;
 if v_t.join_approval='admin' then
   if v_actor<>v_t.owner_id then raise exception 'Admin approval required'; end if;
 elsif v_t.join_approval='participants' then
   if not exists(select 1 from public.athlth_tournament_entries
     where tournament_id=v_t.id and user_id=v_actor
       and response='accepted' and removed_at is null)
   then raise exception 'Only accepted participants may vote'; end if;
 else raise exception 'No approval required'; end if;
 insert into public.athlth_tournament_invite_votes(
    request_id,voter_id,approved
 ) values(p_request,v_actor,p_approved);
 if not p_approved then
   update public.athlth_tournament_invite_requests
   set state='declined',resolved_at=now() where id=p_request;
   return false;
 end if;
 if v_t.join_approval='participants' then
   select count(*) into v_expected
     from public.athlth_tournament_entries
     where tournament_id=v_t.id and response='accepted'
       and removed_at is null;
   select count(*) into v_given
     from public.athlth_tournament_invite_votes
     where request_id=p_request and approved=true;
   if v_given<v_expected then return false; end if;
 end if;
 perform private.athlth_competition_activate_invite(
   v_t.id,v_request.nominee_id,v_actor);
 update public.athlth_tournament_invite_requests
   set state='approved',resolved_at=now() where id=p_request;
 return true;
end;
$fn$;
revoke all on function public.athlth_tournament_propose_invite(uuid,uuid),
 public.athlth_tournament_review_invite(uuid,boolean)
 from public,anon;
grant execute on function public.athlth_tournament_propose_invite(uuid,uuid),
 public.athlth_tournament_review_invite(uuid,boolean)
 to authenticated;
revoke all on function private.athlth_competition_activate_invite(uuid,uuid,uuid)
 from public,anon,authenticated;