create index if not exists direct_conversations_requested_by_idx
  on public.direct_conversations(requested_by)
  where requested_by is not null;
