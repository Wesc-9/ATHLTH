-- Presence is room-scoped, expires automatically, and never contains location.
create table public.social_workout_room_presence (
 source_workout_id uuid not null references public.social_workout_draft_lobbies(source_workout_id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 status text not null check(status in ('viewing','editing','away')),
 updated_at timestamptz not null default now(),
 primary key(source_workout_id,user_id)
);
create table public.social_workout_room_history (
 source_workout_id uuid not null references public.social_workout_draft_lobbies(source_workout_id) on delete cascade,
 revision integer not null check(revision > 1),
 actor_id uuid not null references auth.users(id) on delete cascade,
 changed_fields text[] not null,
 created_at timestamptz not null default now(),
 primary key(source_workout_id,revision)
);
alter table public.social_workout_room_presence enable row level security;
alter table public.social_workout_room_history enable row level security;
revoke all on public.social_workout_room_presence,public.social_workout_room_history from public,anon,authenticated;
grant select on public.social_workout_room_presence,public.social_workout_room_history to authenticated;
grant insert(source_workout_id,user_id,status),update(status) on public.social_workout_room_presence to authenticated;
create policy room_presence_read on public.social_workout_room_presence for select to authenticated using (
 exists(select 1 from public.social_workout_draft_lobbies d where d.source_workout_id=social_workout_room_presence.source_workout_id and d.cancelled_at is null and (select auth.uid()) in(d.owner_id,d.partner_id) and not private.is_blocked(case when (select auth.uid())=d.owner_id then d.partner_id else d.owner_id end)));
create policy room_presence_insert on public.social_workout_room_presence for insert to authenticated with check (
 user_id=(select auth.uid()) and exists(select 1 from public.social_workout_draft_lobbies d where d.source_workout_id=social_workout_room_presence.source_workout_id and d.cancelled_at is null and (select auth.uid()) in(d.owner_id,d.partner_id) and not private.is_blocked(case when (select auth.uid())=d.owner_id then d.partner_id else d.owner_id end)));
create policy room_presence_update on public.social_workout_room_presence for update to authenticated using (user_id=(select auth.uid())) with check (
 user_id=(select auth.uid()) and exists(select 1 from public.social_workout_draft_lobbies d where d.source_workout_id=social_workout_room_presence.source_workout_id and d.cancelled_at is null and (select auth.uid()) in(d.owner_id,d.partner_id) and not private.is_blocked(case when (select auth.uid())=d.owner_id then d.partner_id else d.owner_id end)));
create policy room_history_read on public.social_workout_room_history for select to authenticated using (
 exists(select 1 from public.social_workout_draft_lobbies d where d.source_workout_id=social_workout_room_history.source_workout_id and (select auth.uid()) in(d.owner_id,d.partner_id) and not private.is_blocked(case when (select auth.uid())=d.owner_id then d.partner_id else d.owner_id end)));
create function private.stamp_workout_room_presence() returns trigger language plpgsql set search_path=pg_catalog as $$ begin new.updated_at=now(); return new; end $$;
create trigger stamp_workout_room_presence before insert or update on public.social_workout_room_presence for each row execute function private.stamp_workout_room_presence();
-- Server-owned history and notification events. Never include private recipe
-- details, chat text, or meeting coordinates in notification payloads.
create function private.notify_workout_room(p_source uuid,p_actor uuid,p_title text,p_message text) returns void
language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v_recipient uuid;
begin
 select case when owner_id=p_actor then partner_id else owner_id end into v_recipient
 from public.social_workout_draft_lobbies where source_workout_id=p_source and cancelled_at is null and p_actor in(owner_id,partner_id);
 if v_recipient is null or not exists(select 1 from public.profiles where id=v_recipient) or not exists(select 1 from public.profiles where id=p_actor) or private.is_blocked(v_recipient) then return; end if;
 if exists(select 1 from public.social_inbox_events where recipient_id=v_recipient and actor_id=p_actor and entity_id=p_source and entity_type='shared_workout_room' and title=p_title and read_at is null and created_at>now()-interval '2 minutes') then return; end if;
 insert into public.social_inbox_events(recipient_id,actor_id,kind,title,message,entity_type,entity_id)
 values(v_recipient,p_actor,'train_together_chat',p_title,p_message,'shared_workout_room',p_source);
end $$;
create function private.record_workout_room_revision() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,private as $$
declare v_actor uuid:=auth.uid(); v_fields text[];
begin
 if new.revision<=old.revision or v_actor is null or v_actor not in(new.owner_id,new.partner_id) then return new; end if;
 select coalesce(array_agg(k order by k),'{}'::text[]) into v_fields from (
 select jsonb_object_keys(old.workout_snapshot::jsonb) k union select jsonb_object_keys(new.workout_snapshot::jsonb) k
 ) keys where old.workout_snapshot::jsonb->k is distinct from new.workout_snapshot::jsonb->k;
 insert into public.social_workout_room_history(source_workout_id,revision,actor_id,changed_fields) values(new.source_workout_id,new.revision,v_actor,v_fields);
 perform private.notify_workout_room(new.source_workout_id,v_actor,'Shared workout updated','Review the latest version of your shared workout.');
 return new;
end $$;
create trigger record_workout_room_revision after update of revision on public.social_workout_draft_lobbies for each row execute function private.record_workout_room_revision();
create function private.notify_workout_room_chat() returns trigger language plpgsql security definer set search_path=pg_catalog,public,private as $$
begin perform private.notify_workout_room(new.source_workout_id,new.sender_id,'New shared workout message','New message in your shared workout.'); return new; end $$;
create trigger notify_workout_room_chat after insert on public.social_workout_room_messages for each row execute function private.notify_workout_room_chat();
revoke all on function private.notify_workout_room(uuid,uuid,text,text),private.record_workout_room_revision(),private.notify_workout_room_chat(),private.stamp_workout_room_presence() from public,anon,authenticated;
