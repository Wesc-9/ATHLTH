
-- Terminal cancellation for private planned Train Together invitations.
-- Keep the source UUID and historical message; never delete recordings.
alter table public.social_workout_draft_lobbies
  add column if not exists cancelled_at timestamptz;

create or replace function private.train_together_is_cancellation(
  p_payload text, p_source uuid, p_owner uuid
) returns boolean
language sql immutable
set search_path = pg_catalog
as $$
  select case when pg_input_is_valid(p_payload, 'jsonb') then
    coalesce((p_payload::jsonb ->> 'kind') = 'cancelled'
      and lower(p_payload::jsonb ->> 'sourceWorkoutID') = p_source::text
      and lower(p_payload::jsonb ->> 'organizerID') = p_owner::text, false)
  else false end
$$;

create or replace function private.train_together_invitation_withdrawn(
  p_source uuid, p_owner uuid, p_partner uuid
) returns boolean
language sql security definer
set search_path = pg_catalog, public, private
as $$
  select exists (
    select 1 from public.direct_messages m
    where m.attachment_kind = 'workout' and m.share_version = 6
      and m.source_object_id = p_source and m.source_owner_id = p_owner
      and m.sender_id = p_owner and m.deleted_at is null
      and (p_partner is null or m.recipient_id = p_partner)
      and private.train_together_is_cancellation(
        m.attachment_payload, p_source, p_owner)
  )
$$;

-- Reconcile only proven historical cancellations, retaining the document.
update public.social_workout_draft_lobbies d
set cancelled_at = now(), owner_approved_revision = null,
    partner_approved_revision = null, updated_at = now()
where d.cancelled_at is null and private.train_together_invitation_withdrawn(
  d.source_workout_id, d.owner_id, d.partner_id);

create or replace function private.guard_train_together_draft_terminal()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
begin
  if tg_op = 'UPDATE' then
    if old.cancelled_at is not null then
      raise exception 'Train Together invitation was withdrawn';
    end if;
    if new.cancelled_at is not null then
      if (auth.uid() is not null and auth.uid() is distinct from old.owner_id)
        or new.owner_approved_revision is not null
        or new.partner_approved_revision is not null then
        raise exception 'Only the organizer can withdraw this invitation';
      end if;
      return new;
    end if;
  end if;
  if new.cancelled_at is not null or private.train_together_invitation_withdrawn(
    new.source_workout_id, new.owner_id, new.partner_id) then
    raise exception 'Train Together invitation was withdrawn';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_train_together_draft_terminal on public.social_workout_draft_lobbies;
create trigger guard_train_together_draft_terminal
before insert or update on public.social_workout_draft_lobbies
for each row execute function private.guard_train_together_draft_terminal();

create or replace function private.guard_train_together_message_lifecycle()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_partner uuid;
begin
  if new.attachment_kind is distinct from 'workout'
     or new.share_version not between 2 and 6
     or new.source_object_id is null or new.source_owner_id is null then
    return new;
  end if;
  v_partner := case when new.sender_id = new.source_owner_id then new.recipient_id
    when new.recipient_id = new.source_owner_id then new.sender_id end;
  if v_partner is null then return new; end if;

  if new.share_version = 6 and private.train_together_is_cancellation(
    new.attachment_payload, new.source_object_id, new.source_owner_id) then
    if new.sender_id is distinct from new.source_owner_id
      or auth.uid() is distinct from new.source_owner_id
      or not exists (
        select 1 from public.direct_messages m
        where m.conversation_id = new.conversation_id
          and m.attachment_kind = 'workout' and m.share_version = 2
          and m.sender_id = new.source_owner_id and m.recipient_id = v_partner
          and m.source_object_id = new.source_object_id
          and m.source_owner_id = new.source_owner_id and m.deleted_at is null
      ) then
      raise exception 'Only the original organizer can withdraw an invitation';
    end if;
    if private.train_together_invitation_withdrawn(
      new.source_object_id, new.source_owner_id, v_partner) then
      return null;
    end if;

    -- Synchronize with the coordinated start and participant recording gate.
    perform 1 from public.social_workout_sessions s
      where s.creator_id = new.source_owner_id
        and lower(s.invite_payload #>> '{workout,id}') = new.source_object_id::text
      for update;
    if exists (
      select 1 from public.social_workout_sessions s
      join public.social_workout_participants p on p.session_id = s.id
      where s.creator_id = new.source_owner_id
        and lower(s.invite_payload #>> '{workout,id}') = new.source_object_id::text
        and p.workout_started_at is not null
    ) then
      raise exception 'The shared workout has already started';
    end if;

    update public.social_workout_draft_lobbies d
      set cancelled_at = now(), owner_approved_revision = null,
          partner_approved_revision = null, updated_at = now()
      where d.source_workout_id = new.source_object_id
        and d.owner_id = new.source_owner_id and d.partner_id = v_partner
        and d.cancelled_at is null;
    update public.social_workout_sessions s
      set status = 'cancelled'
      where s.creator_id = new.source_owner_id and s.status = 'active'
        and lower(s.invite_payload #>> '{workout,id}') = new.source_object_id::text;
    return new;
  end if;

  if private.train_together_invitation_withdrawn(
    new.source_object_id, new.source_owner_id, v_partner) then
    raise exception 'Train Together invitation was withdrawn';
  end if;
  return new;
end;
$$;

-- Runs after the original sender/conversation authorization trigger.
drop trigger if exists train_together_message_lifecycle_guard on public.direct_messages;
create trigger train_together_message_lifecycle_guard
before insert on public.direct_messages
for each row execute function private.guard_train_together_message_lifecycle();

create or replace function private.guard_train_together_terminal_start()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_source uuid;
  v_cancelled timestamptz;
  v_text text;
begin
  if tg_op = 'UPDATE' then
    if new.coordinated_start_at is null or
       new.coordinated_start_at is not distinct from old.coordinated_start_at then
      return new;
    end if;
  elsif new.status <> 'active' then
    return new;
  end if;
  v_text := new.invite_payload #>> '{workout,id}';
  if v_text is null or not pg_input_is_valid(v_text, 'uuid') then return new; end if;
  v_source := v_text::uuid;
  select d.cancelled_at into v_cancelled
    from public.social_workout_draft_lobbies d
    where d.source_workout_id = v_source and d.owner_id = new.creator_id
    for share;
  if v_cancelled is not null or private.train_together_invitation_withdrawn(
    v_source, new.creator_id, null) then
    raise exception 'Train Together invitation was withdrawn';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_train_together_terminal_start on public.social_workout_sessions;
create trigger guard_train_together_terminal_start
before insert or update of coordinated_start_at on public.social_workout_sessions
for each row execute function private.guard_train_together_terminal_start();

create or replace function private.guard_train_together_cancelled_participant()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public, private
as $$
declare v_status text;
begin
  if (new.ready_at is not null and new.ready_at is distinct from old.ready_at)
     or (new.workout_started_at is not null
         and new.workout_started_at is distinct from old.workout_started_at) then
    select status into v_status from public.social_workout_sessions
      where id = new.session_id for share;
    if v_status = 'cancelled' then
      raise exception 'The shared workout was cancelled';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_train_together_cancelled_participant on public.social_workout_participants;
create trigger guard_train_together_cancelled_participant
before update of ready_at, workout_started_at on public.social_workout_participants
for each row execute function private.guard_train_together_cancelled_participant();

revoke all on function private.train_together_is_cancellation(text,uuid,uuid)
  from public, anon, authenticated;
revoke all on function private.train_together_invitation_withdrawn(uuid,uuid,uuid)
  from public, anon, authenticated;
revoke all on function private.guard_train_together_draft_terminal()
  from public, anon, authenticated;
revoke all on function private.guard_train_together_message_lifecycle()
  from public, anon, authenticated;
revoke all on function private.guard_train_together_terminal_start()
  from public, anon, authenticated;
revoke all on function private.guard_train_together_cancelled_participant()
  from public, anon, authenticated;
