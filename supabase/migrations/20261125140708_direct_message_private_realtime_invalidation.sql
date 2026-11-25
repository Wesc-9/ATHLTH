-- Private, content-free invalidation; authenticated REST remains authoritative.
-- No raw direct_messages or private receipt table is published.
create policy athlth_direct_broadcast_receive_own
on realtime.messages for select to authenticated
using (
  extension = 'broadcast'
  and (select auth.uid()) is not null
  and (select realtime.topic()) like 'athlth-direct:' || (select auth.uid())::text || ':%'
);

create function private.athlth_signal_direct_thread()
returns trigger language plpgsql security definer set search_path='' as $$
declare a uuid; b uuid; thread uuid; actor uuid := auth.uid();
begin
  if tg_table_name = 'direct_messages' then
    -- Private read timestamps live outside this table. A hidden read must
    -- never send a hint to the sender (even an otherwise empty hint).
    if tg_op = 'UPDATE' then
      if new.read_at is not distinct from old.read_at
         and new.deleted_at is not distinct from old.deleted_at then return new; end if;
    end if;
    if tg_op = 'DELETE' then
      a := old.sender_id; b := old.recipient_id; thread := old.conversation_id;
    else
      a := new.sender_id; b := new.recipient_id; thread := new.conversation_id;
    end if;
  else
    if tg_op = 'UPDATE' then
      if new.request_status is not distinct from old.request_status then return new; end if;
    end if;
    a := new.user_a; b := new.user_b; thread := new.id;
  end if;
  -- This is an internal trigger on already-authorized writes, not an RPC.
  if actor is not null and actor is distinct from a and actor is distinct from b then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  begin
    perform realtime.send('{}'::jsonb, 'refresh', 'athlth-direct:' || a::text || ':' || thread::text, true);
    if b is distinct from a then
      perform realtime.send('{}'::jsonb, 'refresh', 'athlth-direct:' || b::text || ':' || thread::text, true);
    end if;
  exception when others then
    -- Socket infrastructure is optional and must not fail a durable send.
    raise warning 'Direct thread invalidation unavailable';
  end;
  if tg_op = 'DELETE' then return old; else return new; end if;
end; $$;
revoke all on function private.athlth_signal_direct_thread() from public, anon, authenticated;
create trigger athlth_signal_direct_message
after insert or update of read_at, deleted_at or delete on public.direct_messages
for each row execute function private.athlth_signal_direct_thread();
create trigger athlth_signal_direct_conversation
after insert or update of request_status on public.direct_conversations
for each row execute function private.athlth_signal_direct_thread();
