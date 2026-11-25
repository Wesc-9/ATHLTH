-- Rollback-only tests. No real accounts, messages, or delivery events.
begin;
create temp table direct_messages (
 sender_id uuid, recipient_id uuid, conversation_id uuid,
 read_at timestamptz, deleted_at timestamptz
);
create trigger test_direct_hint after insert or update of read_at, deleted_at or delete on pg_temp.direct_messages
for each row execute function private.athlth_signal_direct_thread();
do $$
declare
 a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); c uuid := gen_random_uuid(); n int;
 ta text := 'athlth-direct:' || a::text || ':' || c::text;
 tb text := 'athlth-direct:' || b::text || ':' || c::text;
begin
 perform set_config('request.jwt.claim.sub',a::text,true);
 insert into pg_temp.direct_messages(sender_id,recipient_id,conversation_id) values(a,b,c);
 select count(*) into n from realtime.messages where topic in (ta,tb) and event='refresh' and private and payload - 'id'='{}'::jsonb;
 if n <> 2 then raise exception 'expected two content-free insert signals, got %',n; end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 update pg_temp.direct_messages set read_at=null;
 select count(*) into n from realtime.messages where topic in (ta,tb) and event='refresh';
 if n <> 2 then raise exception 'hidden receipt generated a signal'; end if;
 update pg_temp.direct_messages set read_at=now();
 select count(*) into n from realtime.messages where topic in (ta,tb) and event='refresh';
 if n <> 4 then raise exception 'visible receipt not signalled'; end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 delete from pg_temp.direct_messages;
 select count(*) into n from realtime.messages where topic in (ta,tb) and event='refresh';
 if n <> 6 then raise exception 'delete not signalled'; end if;
end $$;
rollback;

begin;
select realtime.send('{}'::jsonb,'refresh','athlth-direct:4a100000-0000-4000-8000-000000000001:4a100000-0000-4000-8000-000000000003',true);
select realtime.send('{}'::jsonb,'refresh','athlth-direct:4a100000-0000-4000-8000-000000000002:4a100000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $$
declare a text := 'athlth-direct:4a100000-0000-4000-8000-000000000001:4a100000-0000-4000-8000-000000000003'; b text := 'athlth-direct:4a100000-0000-4000-8000-000000000002:4a100000-0000-4000-8000-000000000003'; n int;
begin
 perform set_config('request.jwt.claim.sub','4a100000-0000-4000-8000-000000000001',true);
 perform set_config('realtime.topic',a,true);
 select count(*) into n from realtime.messages where topic in(a,b);
 if n <> 1 then raise exception 'own topic must reveal one row, got %',n; end if;
 perform set_config('realtime.topic',b,true);
 select count(*) into n from realtime.messages where topic in(a,b);
 if n <> 0 then raise exception 'foreign account topic exposed'; end if;
end $$;
reset role;
set local role anon;
do $$ declare n int; begin
 perform set_config('realtime.topic','athlth-direct:4a100000-0000-4000-8000-000000000001:4a100000-0000-4000-8000-000000000003',true);
 select count(*) into n from realtime.messages where topic like 'athlth-direct:4a100000-0000-4000-8000-000000000001:%';
 if n <> 0 then raise exception 'anonymous access exposed'; end if;
end $$;
rollback;
