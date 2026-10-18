-- RLS integration test: online indicator is opt-in and mutual-follow only.
-- Run against disposable DB; all fixtures are rolled back.
begin;

insert into auth.users (id) values
  ('18200000-0000-0000-0000-000000000001'),
  ('18200000-0000-0000-0000-000000000002'),
  ('18200000-0000-0000-0000-000000000003');

-- Owner explicitly enables the indicator; the default is off.
insert into public.profile_social_settings (user_id, show_online_status)
values ('18200000-0000-0000-0000-000000000001', true)
on conflict (user_id) do update set show_online_status = true;

insert into public.social_online_presence (user_id, is_online, updated_at)
values ('18200000-0000-0000-0000-000000000001', true, now());

-- A follows B, but B does not follow A: visibility must remain denied.
insert into public.profile_follows (follower_id, following_id) values
  ('18200000-0000-0000-0000-000000000002',
   '18200000-0000-0000-0000-000000000001');

set local role authenticated;
set local request.jwt.claim.sub = '18200000-0000-0000-0000-000000000002';
do $$ begin
  if private.can_view_online_status('18200000-0000-0000-0000-000000000001')
    or exists (select 1 from public.social_online_presence
               where user_id = '18200000-0000-0000-0000-000000000001')
  then raise exception 'One-way follower learned online status'; end if;
end $$;
reset role;

-- As soon as B also follows A, the online indicator is visible.
insert into public.profile_follows (follower_id, following_id) values
  ('18200000-0000-0000-0000-000000000001',
   '18200000-0000-0000-0000-000000000002');

set local role authenticated;
set local request.jwt.claim.sub = '18200000-0000-0000-0000-000000000002';
do $$ begin
  if not private.can_view_online_status('18200000-0000-0000-0000-000000000001')
    or not exists (select 1 from public.social_online_presence
                   where user_id = '18200000-0000-0000-0000-000000000001')
  then raise exception 'Mutual follow lost consented online visibility'; end if;
end $$;
reset role;

-- Both sides following cannot override opting out.
update public.profile_social_settings
set show_online_status = false
where user_id = '18200000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub = '18200000-0000-0000-0000-000000000002';
do $$ begin
  if private.can_view_online_status('18200000-0000-0000-0000-000000000001')
    or exists (select 1 from public.social_online_presence
               where user_id = '18200000-0000-0000-0000-000000000001')
  then raise exception 'Online status leaked despite opting out'; end if;
end $$;
reset role;

-- Blocking also overrides both mutual follow and opt-in.
update public.profile_social_settings
set show_online_status = true
where user_id = '18200000-0000-0000-0000-000000000001';
insert into public.user_blocks (blocker_id, blocked_id) values
  ('18200000-0000-0000-0000-000000000001',
   '18200000-0000-0000-0000-000000000002');

set local role authenticated;
set local request.jwt.claim.sub = '18200000-0000-0000-0000-000000000002';
do $$ begin
  if private.can_view_online_status('18200000-0000-0000-0000-000000000001')
    or exists (select 1 from public.social_online_presence
               where user_id = '18200000-0000-0000-0000-000000000001')
  then raise exception 'Blocked account read online status'; end if;
end $$;
reset role;

-- The owner retains access to their own row.
set local role authenticated;
set local request.jwt.claim.sub = '18200000-0000-0000-0000-000000000001';
do $$ begin
  if not exists (select 1 from public.social_online_presence
                 where user_id = '18200000-0000-0000-0000-000000000001')
  then raise exception 'Owner lost access to own presence'; end if;
end $$;
reset role;

select 'Mutual online presence RLS checks passed' as result;
rollback;
