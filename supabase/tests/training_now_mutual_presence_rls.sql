-- Social 'Training now' is opt-in, fresh and visible to mutual follows only.
begin;
insert into auth.users (id) values
 ('18300000-0000-0000-0000-000000000001'),
 ('18300000-0000-0000-0000-000000000002'),
 ('18300000-0000-0000-0000-000000000003');
insert into public.profile_social_settings (user_id, share_training_presence)
values ('18300000-0000-0000-0000-000000000001', true)
on conflict (user_id) do update set share_training_presence = true;
insert into public.social_presence (user_id, state, updated_at)
values ('18300000-0000-0000-0000-000000000001', 'training', now())
on conflict (user_id) do update set state='training', updated_at=now();
insert into public.profile_follows(follower_id, following_id) values
('18300000-0000-0000-0000-000000000002', '18300000-0000-0000-0000-000000000001');

set local role authenticated;
set local request.jwt.claim.sub='18300000-0000-0000-0000-000000000002';
do $$ begin
 if exists(select 1 from public.social_presence
           where user_id='18300000-0000-0000-0000-000000000001')
 then raise exception 'One-way follower saw workout status'; end if;
end $$;
reset role;

insert into public.profile_follows(follower_id, following_id) values
('18300000-0000-0000-0000-000000000001', '18300000-0000-0000-0000-000000000002');
set local role authenticated;
set local request.jwt.claim.sub='18300000-0000-0000-0000-000000000002';
do $$ begin
 if not exists(select 1 from public.social_presence
               where user_id='18300000-0000-0000-0000-000000000001')
 then raise exception 'Mutual follower lost consented training status'; end if;
end $$;
reset role;

update public.profile_social_settings
set share_training_presence=false
where user_id='18300000-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claim.sub='18300000-0000-0000-0000-000000000002';
do $$ begin
 if exists(select 1 from public.social_presence
           where user_id='18300000-0000-0000-0000-000000000001')
 then raise exception 'Disabled training sharing was exposed'; end if;
end $$;
reset role;

update public.profile_social_settings
set share_training_presence=true
where user_id='18300000-0000-0000-0000-000000000001';
update public.social_presence
set updated_at=now()-interval '5 minutes'
where user_id='18300000-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claim.sub='18300000-0000-0000-0000-000000000002';
do $$ begin
 if exists(select 1 from public.social_presence
           where user_id='18300000-0000-0000-0000-000000000001')
 then raise exception 'Stale workout status was exposed'; end if;
end $$;
reset role;

update public.social_presence set updated_at=now()
where user_id='18300000-0000-0000-0000-000000000001';
insert into public.user_blocks(blocker_id, blocked_id) values
('18300000-0000-0000-0000-000000000001','18300000-0000-0000-0000-000000000002');
set local role authenticated;
set local request.jwt.claim.sub='18300000-0000-0000-0000-000000000002';
do $$ begin
 if exists(select 1 from public.social_presence
           where user_id='18300000-0000-0000-0000-000000000001')
 then raise exception 'Blocked user learned workout presence'; end if;
end $$;
reset role;
select 'Mutual training presence RLS tests passed';
rollback;
