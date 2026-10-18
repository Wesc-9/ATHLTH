-- v1.8.1: first-class exercise sharing and request attachments.
-- Preserve the one-request limit, recipient privacy settings, blocks and
-- explicit acceptance requirements enforced by guard_direct_message_insert.
alter table public.direct_messages
  drop constraint if exists direct_messages_attachment_kind_check;
alter table public.direct_messages
  add constraint direct_messages_attachment_kind_check
  check (
    attachment_kind is null or
    attachment_kind in (
      'workout', 'training_plan', 'exercise', 'running_workout', 'route', 'challenge'
    )
  );

drop policy if exists direct_messages_insert_sender on public.direct_messages;
create policy direct_messages_insert_sender
on public.direct_messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and recipient_id <> (select auth.uid())
  and exists (
    select 1 from public.direct_conversations c
    where c.id = conversation_id
      and (
        (c.user_a = sender_id and c.user_b = recipient_id)
        or (c.user_b = sender_id and c.user_a = recipient_id)
      )
      and (
        c.request_status = 'accepted'
        or (
          c.request_status = 'pending'
          and c.requested_by = (select auth.uid())
          and (
            coalesce(char_length(btrim(body)), 0) > 0
            or (
              attachment_kind is not null
              and attachment_payload is not null
              and octet_length(attachment_payload) > 0
            )
          )
          and not exists (
            select 1 from public.direct_messages prior
            where prior.conversation_id = c.id
          )
        )
      )
  )
);
