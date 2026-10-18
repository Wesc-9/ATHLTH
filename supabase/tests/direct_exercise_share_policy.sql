-- Verify that the exercise type and request attachment policy exist.
-- PostgreSQL may pretty-print 'not exists' as 'not (exists (...))';
-- check independently for the guard conditions instead of specific spacing.
do $$
declare
  kind_constraint text;
  sender_policy text;
begin
  select pg_get_constraintdef(c.oid) into kind_constraint
  from pg_constraint c
  where c.conrelid = 'public.direct_messages'::regclass
    and c.conname = 'direct_messages_attachment_kind_check';

  if kind_constraint is null or position('EXERCISE' in upper(kind_constraint)) = 0 then
    raise exception 'Missing exercise attachment check constraint';
  end if;

  select with_check into sender_policy
  from pg_policies
  where schemaname = 'public'
    and tablename = 'direct_messages'
    and policyname = 'direct_messages_insert_sender';

  if sender_policy is null
    or position('PENDING' in upper(sender_policy)) = 0
    or position('ATTACHMENT_KIND' in upper(sender_policy)) = 0
    or position('EXISTS' in upper(sender_policy)) = 0
    or position('RECIPIENT_ID' in upper(sender_policy)) = 0
  then
    raise exception 'Direct message insert policy is missing request safeguards';
  end if;
end
$$;
