-- Actual RLS integration check: first exercise attachment to an unknown
-- athlete is delivered as one request, never an unlimited DM channel.
begin;
insert into auth.users(id) values
 ('18100000-0000-0000-0000-000000000001'),
 ('18100000-0000-0000-0000-000000000002');

insert into public.direct_conversations (
 id, user_a, user_b, request_status, requested_by
) values (
 '18100000-0000-0000-0000-000000000010',
 '18100000-0000-0000-0000-000000000001',
 '18100000-0000-0000-0000-000000000002',
 'pending', '18100000-0000-0000-0000-000000000001'
);

set local role authenticated;
set local request.jwt.claim.sub='18100000-0000-0000-0000-000000000001';

insert into public.direct_messages (
 conversation_id, sender_id, recipient_id, attachment_kind,
 attachment_title, attachment_payload
) values (
 '18100000-0000-0000-0000-000000000010',
 '18100000-0000-0000-0000-000000000001',
 '18100000-0000-0000-0000-000000000002',
 'exercise','Test private exercise',
 '{"name":"Custom Row","sourceID":null,"sourceIdentifier":null,"snapshot":null}'
);

do $$
declare
  second_insert_succeeded boolean := false;
begin
  begin
    insert into public.direct_messages (
      conversation_id, sender_id, recipient_id, body
    ) values (
      '18100000-0000-0000-0000-000000000010',
      '18100000-0000-0000-0000-000000000001',
      '18100000-0000-0000-0000-000000000002',
      'A second unaccepted message should be blocked'
    );
    second_insert_succeeded := true;
  exception when others then
    null; -- Expected RLS or guard rejection.
  end;
  if second_insert_succeeded then
    raise exception 'Unaccepted recipient received a second message';
  end if;
end $$;

set local request.jwt.claim.sub='18100000-0000-0000-0000-000000000002';
do $$
begin
  if (select count(*) from public.direct_messages
      where conversation_id = '18100000-0000-0000-0000-000000000010') <> 1
  then
    raise exception 'Recipient could not review the first share in inbox';
  end if;
end $$;
reset role;
rollback;
