-- Notify the organizer when invitees respond, and inform the full
-- competition when a replacement request is approved or rejected.
-- These events use the established privacy-filtered Inbox/APNs pipeline.
create or replace function private.arena_notify_invitation_response()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare v_owner uuid;
begin
  if old.response = new.response
    or new.response not in ('accepted','declined') then return new; end if;
  select owner_id into v_owner from public.arena_series where id=new.series_id;
  if v_owner is null or v_owner = new.user_id then return new; end if;
  insert into public.social_inbox_events(
    recipient_id,kind,title,message,entity_type,entity_id,actor_id
  ) values(
    v_owner,'arena_round','Arena – svar på invitasjon',
    case when new.response='accepted'
      then 'En deltaker har godtatt invitasjonen.'
      else 'En deltaker har avslått invitasjonen. Du kan velge en erstatter før start.'
    end,
    'arena_series',new.series_id,new.user_id
  );
  return new;
end;
$$;
drop trigger if exists arena_notify_invitation_response
 on public.arena_series_members;
create trigger arena_notify_invitation_response
after update of response on public.arena_series_members
for each row execute function private.arena_notify_invitation_response();

create or replace function private.arena_notify_replacement_decision()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public,private as $$
begin
 if old.status = new.status
    or new.status not in ('approved','rejected') then return new; end if;
 insert into public.social_inbox_events(
    recipient_id,kind,title,message,entity_type,entity_id,actor_id
 )
 select recipient,'arena_replacement','Arena – bytte av deltaker',
   case when new.status='approved'
     then 'Erstatteren er godkjent av gruppen.'
     else 'Forslaget til erstatter er avslått.'
   end,
   'arena_series',new.series_id,new.proposed_by
 from (
   select m.user_id as recipient
     from public.arena_series_members m
     where m.series_id=new.series_id
       and m.response='accepted' and m.user_id is not null
   union select new.nominee_id
 ) recipients where recipient is not null;
 return new;
end;
$$;
drop trigger if exists arena_notify_replacement_decision
 on public.arena_replacement_proposals;
create trigger arena_notify_replacement_decision
after update of status on public.arena_replacement_proposals
for each row execute function private.arena_notify_replacement_decision();
revoke all on function private.arena_notify_invitation_response(),
 private.arena_notify_replacement_decision()
 from public,anon,authenticated;
