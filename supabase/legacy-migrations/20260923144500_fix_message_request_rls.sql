-- Avoid self-referencing RLS on direct_messages.
-- The one-request-message limit is enforced by the SECURITY DEFINER insert guard.

drop policy if exists direct_messages_insert_sender
  on public.direct_messages;

create policy direct_messages_insert_sender
  on public.direct_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and recipient_id <> (select auth.uid())
    and exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and (
          (c.user_a = sender_id and c.user_b = recipient_id)
          or
          (c.user_b = sender_id and c.user_a = recipient_id)
        )
        and c.request_status in ('pending', 'accepted')
    )
  );
