-- Fix organizer cancellation/completion rollback.
-- The lifecycle RPC used to update the event first and then insert the
-- system chat message. Event-chat RLS intentionally blocks inserts once an
-- event is completed/cancelled, so that ordering rolled the whole transaction
-- back. Insert the system message while the event is still open, then close it.

create or replace function public.community_event_set_lifecycle(
  p_event_id uuid,
  p_status text
)
returns text
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_creator uuid;
  v_current text;
  v_system_body text;
begin
  if p_status not in ('live','completed','cancelled') then
    raise exception 'Unsupported event lifecycle status';
  end if;

  select creator_id, status
    into v_creator, v_current
  from public.community_events
  where id = p_event_id
  for update;

  if v_creator is null then
    raise exception 'Event not found';
  end if;

  if v_creator <> (select auth.uid()) then
    raise exception 'Only the organizer can change event status';
  end if;

  if v_current in ('completed','cancelled') then
    if v_current = p_status then
      return v_current;
    end if;

    raise exception 'A closed event cannot change status';
  end if;

  if p_status = 'live' and v_current <> 'upcoming' then
    raise exception 'Only a planned event can be started';
  end if;

  v_system_body :=
    case p_status
      when 'live' then 'event_started'
      when 'completed' then 'event_completed'
      when 'cancelled' then 'event_cancelled'
      else null
    end;

  if v_system_body is not null then
    insert into public.community_event_messages (
      event_id,
      author_id,
      kind,
      body
    )
    values (
      p_event_id,
      (select auth.uid()),
      'system',
      v_system_body
    );
  end if;

  update public.community_events
  set
    status = p_status,
    updated_at = now()
  where id = p_event_id;

  return p_status;
end;
$$;

revoke all on function public.community_event_set_lifecycle(uuid, text)
  from public;

grant execute
  on function public.community_event_set_lifecycle(uuid, text)
  to authenticated;
