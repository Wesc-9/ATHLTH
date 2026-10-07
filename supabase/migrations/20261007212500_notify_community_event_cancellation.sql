-- Notify every event participant when an organizer cancels an event.
-- The lifecycle RPC owns the complete transaction: chat status, event status
-- and participant inbox rows. social_inbox_events already fans inserts out
-- through the APNs trigger.

create or replace function public.community_event_set_lifecycle(
  p_event_id uuid,
  p_status text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_creator uuid;
  v_current text;
  v_title text;
  v_system_body text;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  if p_status not in ('live','completed','cancelled') then
    raise exception 'Unsupported event lifecycle status';
  end if;

  select e.creator_id, e.status, e.title
    into v_creator, v_current, v_title
  from public.community_events e
  where e.id = p_event_id
  for update;

  if v_creator is null then
    raise exception 'Event not found';
  end if;

  if v_creator <> v_actor then
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
      v_actor,
      'system',
      v_system_body
    );
  end if;

  update public.community_events
  set
    status = p_status,
    updated_at = now()
  where id = p_event_id;

  if p_status = 'cancelled' then
    insert into public.social_inbox_events (
      recipient_id,
      actor_id,
      kind,
      title,
      message,
      entity_type,
      entity_id
    )
    select
      p.user_id,
      v_actor,
      'group_event',
      'Event cancelled',
      v_title || ' has important changes.',
      'community_event',
      p_event_id
    from public.community_event_participants p
    where p.event_id = p_event_id
      and p.user_id <> v_actor;
  end if;

  return p_status;
end;
$$;

revoke all on function public.community_event_set_lifecycle(uuid, text)
  from public, anon;

grant execute
  on function public.community_event_set_lifecycle(uuid, text)
  to authenticated;
