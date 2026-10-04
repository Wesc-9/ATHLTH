-- Cover direct_messages.sender_id foreign key for message-history lookups and deletes.
create index if not exists direct_messages_sender_idx
  on public.direct_messages(sender_id, created_at desc);
