-- Automatically expire one-off Community events not started within 12 hours.
-- Runs in the database even if no iPhone or Watch has launched ATHLTH.
-- Recurring Club events are preserved until their complete series has ended.
create or replace function private.expire_unstarted_community_events()
returns jsonb
language plpgsql
set search_path = pg_catalog, public, private
as $function$
declare
  v_event record;
  v_personal_count integer := 0;
  v_club_count integer := 0;
  v_cutoff timestamptz := now() - interval '12 hours';
begin
  -- The predicate is part of the atomic write: starting an event before this
  -- update wins the race and protects it from auto-cancellation.
  for v_event in
    update public.community_events e
       set status = 'cancelled', updated_at = now()
     where e.status = 'upcoming'
       and e.starts_at <= v_cutoff
    returning e.id, e.creator_id, e.title
  loop
    v_personal_count := v_personal_count + 1;

    -- Reuse the system message understood by the existing event chat.
    insert into public.community_event_messages (
      event_id, author_id, kind, body
    ) values (v_event.id, v_event.creator_id, 'system', 'event_cancelled');

    -- Notify attendees once, matching the normal organizer cancellation flow.
    insert into public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    )
    select distinct
      p.user_id,
      v_event.creator_id,
      'group_event',
      'Event cancelled',
      v_event.title || ' has been cancelled.',
      'community_event',
      v_event.id
    from public.community_event_participants p
    where p.event_id = v_event.id
      and p.user_id <> v_event.creator_id
      and not exists (
        select 1
          from public.social_inbox_events i
         where i.recipient_id = p.user_id
           and i.entity_type = 'community_event'
           and i.entity_id = v_event.id
           and i.kind = 'group_event'
           and i.title = 'Event cancelled'
      );
  end loop;

  -- A weekly event is a recurring series, not one missed occurrence: do not
  -- accidentally cancel every future week. The ordinary update trigger sends
  -- the Club's event-change notifications to its RSVPed participants.
  with expired_club_events as (
    update public.community_group_events e
       set status = 'cancelled', updated_at = now()
     where e.status = 'upcoming'
       and e.starts_at <= v_cutoff
       and (
         e.repeat_rule is distinct from 'weekly'
         or (e.repeat_until is not null and e.repeat_until <= v_cutoff)
       )
    returning e.id
  )
  select count(*)::integer into v_club_count
  from expired_club_events;

  return jsonb_build_object(
    'community_events_cancelled', v_personal_count,
    'club_events_cancelled', v_club_count
  );
end;
$function$;

revoke all on function private.expire_unstarted_community_events()
from public, anon, authenticated;

select cron.schedule(
  'athlth-expire-unstarted-community-events',
  '*/10 * * * *',
  'select private.expire_unstarted_community_events();'
);
