-- Organizer-only, atomic pre-start invitation changes. Accepted athletes
-- cannot be silently removed, and new nominees re-approve every round.
create or replace function private.arena_change_invitation_impl(
 p_series uuid, p_old_user uuid, p_replacement uuid
) returns text language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare
 v_series public.arena_series%rowtype;
 v_old public.arena_series_members%rowtype;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into v_series from public.arena_series
 where id=p_series for update;
 if not found or v_series.status <> 'draft' then
   raise exception 'Invitations may only change before a competition starts';
 end if;
 if not private.arena_is_organizer(p_series) then
   raise exception 'Only the organizer may change invitations';
 end if;
 select * into v_old from public.arena_series_members
 where series_id=p_series and user_id=p_old_user for update;
 if not found or v_old.response not in ('invited','declined')
    or p_old_user=v_series.owner_id then
   raise exception 'Only unanswered or declined invitations may be changed';
 end if;
 if p_replacement is not null then
   if p_replacement=p_old_user or p_replacement=v_series.owner_id
     or exists(select 1 from public.arena_series_members
               where series_id=p_series and user_id=p_replacement) then
     raise exception 'Select someone who is not already in this competition';
   end if;
   if not private.arena_can_invite(p_replacement) then
     raise exception 'The new athlete does not allow Arena invitations';
   end if;
   if v_series.scope='club' and not exists(
     select 1 from public.community_group_members gm
     where gm.group_id=v_series.club_id and gm.user_id=p_replacement
   ) then raise exception 'Replacement athlete must be a Club member'; end if;
 end if;
 -- Remove the old pending Inbox request so it cannot open a stale invite.
 delete from public.social_inbox_events
 where recipient_id=p_old_user and kind='arena_invite'
   and entity_type='arena_series' and entity_id=p_series;
 delete from public.arena_series_members
 where series_id=p_series and user_id=p_old_user;
 if p_replacement is not null then
   insert into public.arena_series_members(series_id,user_id,response)
   values(p_series,p_replacement,'invited');
   -- Existing invite trigger creates the new inbox event.
   return 'replaced';
 end if;
 return 'removed';
end;
$$;
revoke all on function private.arena_change_invitation_impl(uuid,uuid,uuid)
 from public,anon;
grant execute on function private.arena_change_invitation_impl(uuid,uuid,uuid)
 to authenticated;
create or replace function public.arena_change_invitation(
 p_series uuid,p_old_user uuid,p_replacement uuid
) returns text language sql security invoker
set search_path=pg_catalog,public,private as $$
 select private.arena_change_invitation_impl(p_series,p_old_user,p_replacement);
$$;
revoke all on function public.arena_change_invitation(uuid,uuid,uuid)
 from public,anon;
grant execute on function public.arena_change_invitation(uuid,uuid,uuid)
 to authenticated;
