-- ATHLTH v1.8.1 exercise sharing and first-contact attachment policy.
do $$
declare
  kind_constraint text;
  sender_policy text;
begin
  select pg_get_constraintdef(c.oid)
    into kind_constraint
  from pg_constraint c
  where c.conrelid = 'public.direct_messages'::regclass
    and c.conname = 'direct_messages_attachment_kind_check';

  if kind_constraint is null or position('exercise' in kind_constraint) = 0 then
    raise exception 'Exercise messages are not allowed by direct_messages check constraint';
  end if;

  select with_check into sender_policy
  from pg_policies
  where schemaname = 'public'
    and tablename = 'direct_messages'
    and policyname = 'direct_messages_insert_sender';

  if sender_policy is null
    or position('request_status' in sender_policy) = 0
    or position('attachment_kind IS NOT NULL' in upper(sender_policy)) = 0
    or position('NOT EXISTS' in upper(sender_policy)) = 0
  then
    -- Uppercase checks below normalize policy expression formatting.
    if sender_policy is null
      or position('PENDING' in upper(sender_policy)) = 0
      or position('ATTACHMENT_KIND IS NOT NULL' in upper(sender_policy)) = 0
      or position('NOT EXISTS' in upper(sender_policy)) = 0
    then
      raise exception 'First contact shares must allow one attachment without allowing repeat requests';
    end if;
  end if;
end
$$;
