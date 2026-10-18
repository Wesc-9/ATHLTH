-- v1.8.1 security fix: avoid recursive RLS reads of direct_messages.
-- The SECURITY DEFINER guard_direct_message_insert() trigger locks the
-- conversation FOR UPDATE and rejects a second message while pending.
-- Keep membership and authenticated sender checks in RLS.
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
        )
      )
  )
);
