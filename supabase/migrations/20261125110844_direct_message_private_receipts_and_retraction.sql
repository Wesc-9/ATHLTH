create table private.athlth_message_receipt_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 share_receipts boolean not null default true
);
alter table private.athlth_message_receipt_preferences enable row level security;
revoke all on private.athlth_message_receipt_preferences from public,anon,authenticated;
create table private.athlth_direct_message_reads(
 message_id uuid primary key references public.direct_messages(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 read_at timestamptz not null
);
alter table private.athlth_direct_message_reads enable row level security;
revoke all on private.athlth_direct_message_reads from public,anon,authenticated;
alter table public.social_inbox_events add column direct_message_id uuid references public.direct_messages(id) on delete cascade;
create index social_inbox_events_direct_message_idx on public.social_inbox_events(direct_message_id) where direct_message_id is not null;

create or replace function private.guard_direct_message_update() returns trigger
language plpgsql security definer set search_path='' as $$
declare actual timestamptz; sharing boolean;
begin
 if auth.uid() is distinct from old.recipient_id then raise exception 'Only the recipient can mark a message as read' using errcode='42501'; end if;
 if (to_jsonb(new)-'read_at') is distinct from (to_jsonb(old)-'read_at') then raise exception 'Message content is immutable'; end if;
 sharing := coalesce((select p.share_receipts from private.athlth_message_receipt_preferences p where p.user_id=old.recipient_id),true);
 if new.read_at is not null or old.read_at is not null then
   insert into private.athlth_direct_message_reads(message_id,recipient_id,read_at)
   values(old.id,old.recipient_id,coalesce(old.read_at,now()))
   on conflict(message_id) do nothing;
 end if;
 select r.read_at into actual from private.athlth_direct_message_reads r where r.message_id=old.id;
 if sharing then
   -- Do not expose an earlier private read just because sharing was re-enabled.
   new.read_at := coalesce(old.read_at,case when actual is not null and new.read_at is not null and actual=now() then actual end);
 else new.read_at := null; end if;
 return new;
end; $$;
revoke all on function private.guard_direct_message_update() from public,anon,authenticated;

create or replace function private.athlth_visible_direct_read(p_id uuid,p_recipient uuid,p_public_read timestamptz)
returns timestamptz language sql stable security definer set search_path='' as $$
 select case when auth.uid()=p_recipient then coalesce(
  (select r.read_at from private.athlth_direct_message_reads r where r.message_id=p_id and r.recipient_id=auth.uid()),p_public_read)
 else p_public_read end;
$$;
revoke all on function private.athlth_visible_direct_read(uuid,uuid,timestamptz) from public,anon;
grant execute on function private.athlth_visible_direct_read(uuid,uuid,timestamptz) to authenticated;

create view public.athlth_direct_messages_visible with (security_invoker=true) as
 select m.id,m.conversation_id,m.sender_id,m.recipient_id,m.body,m.attachment_kind,m.attachment_title,m.attachment_subtitle,m.attachment_payload,m.share_version,m.source_object_id,m.source_owner_id,m.created_at,
 private.athlth_visible_direct_read(m.id,m.recipient_id,m.read_at) as read_at,m.deleted_at
 from public.direct_messages m;
revoke all on public.athlth_direct_messages_visible from public,anon,authenticated;
grant select on public.athlth_direct_messages_visible to authenticated;

create function private.athlth_my_read_receipts(p_enabled boolean default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result boolean;
begin
 if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_enabled is not null then
  insert into private.athlth_message_receipt_preferences(user_id,share_receipts) values(uid,p_enabled)
  on conflict(user_id) do update set share_receipts=excluded.share_receipts;
  if not p_enabled then
   update public.direct_messages set read_at=null where recipient_id=uid and read_at is not null;
  end if;
 end if;
 select p.share_receipts into result from private.athlth_message_receipt_preferences p where p.user_id=uid;
 return coalesce(result,true);
end; $$;
revoke all on function private.athlth_my_read_receipts(boolean) from public,anon;
grant execute on function private.athlth_my_read_receipts(boolean) to authenticated;
create function public.athlth_my_read_receipts(p_enabled boolean default null)
returns boolean language sql security invoker set search_path='' as $$
 select private.athlth_my_read_receipts(p_enabled);
$$;
revoke all on function public.athlth_my_read_receipts(boolean) from public,anon;
grant execute on function public.athlth_my_read_receipts(boolean) to authenticated;

create function private.athlth_retract_unread_direct_message(p_message_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare m public.direct_messages%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into m from public.direct_messages where id=p_message_id and sender_id=auth.uid() for update;
 if not found or m.deleted_at is not null or m.attachment_kind is not null or m.read_at is not null then return false; end if;
 if exists(select 1 from private.athlth_direct_message_reads r where r.message_id=m.id) then return false; end if;
 delete from public.direct_messages where id=m.id;
 return true;
end; $$;
revoke all on function private.athlth_retract_unread_direct_message(uuid) from public,anon;
grant execute on function private.athlth_retract_unread_direct_message(uuid) to authenticated;
create function public.athlth_retract_unread_direct_message(p_message_id uuid)
returns boolean language sql security invoker set search_path='' as $$
 select private.athlth_retract_unread_direct_message(p_message_id);
$$;
revoke all on function public.athlth_retract_unread_direct_message(uuid) from public,anon;
grant execute on function public.athlth_retract_unread_direct_message(uuid) to authenticated;

CREATE OR REPLACE FUNCTION private.after_direct_message_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  sender_name text;
  recipient_username text;
  preview text;
  conversation_state text;
  is_mention boolean := false;
begin
  update public.direct_conversations
  set
    last_message_at = new.created_at,
    updated_at = now()
  where id = new.conversation_id;

  select c.request_status
    into conversation_state
  from public.direct_conversations c
  where c.id = new.conversation_id;

  select
    coalesce(nullif(p.display_name, ''), nullif(p.username::text, ''), 'Someone')
  into sender_name
  from public.profiles p
  where p.id = new.sender_id;

  select p.username::text
    into recipient_username
  from public.profiles p
  where p.id = new.recipient_id;

  preview := nullif(btrim(new.body), '');
  if preview is null then
    preview := coalesce(new.attachment_title, 'Shared something with you');
  end if;

  if conversation_state = 'accepted'
     and recipient_username is not null
     and new.body is not null
     and lower(recipient_username) = any(
       coalesce(
         (
           select array_agg(distinct lower(m[1]))
           from regexp_matches(
             lower(new.body),
             '@([a-z0-9_]+)',
             'g'
           ) as m
         ),
         array[]::text[]
       )
     )
     and private.mention_notifications_enabled(new.recipient_id)
  then
    is_mention := true;
  end if;

  insert into public.social_inbox_events(
    recipient_id,
    actor_id,
    kind,
    title,
    message,
    entity_type,
    entity_id,
    direct_message_id
  )
  values (
    new.recipient_id,
    new.sender_id,
    case
      when conversation_state = 'pending'
        then 'message_request'
      when is_mention
        then 'mention'
      else 'message'
    end,
    case
      when conversation_state = 'pending'
        then 'Message request from ' || coalesce(sender_name, 'Someone')
      when is_mention
        then coalesce(sender_name, 'A friend')
      else coalesce(sender_name, 'A friend')
    end,
    left(preview, 240),
    'direct_conversation',
    new.conversation_id,
    new.id
  );

  return new;
end;
$function$
;
