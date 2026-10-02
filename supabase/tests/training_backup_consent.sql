-- Transactional integration test. Uses one existing account, creates only temporary
-- backup/consent rows, and rolls everything back. No personal data is selected.
begin;
select set_config('request.jwt.claim.sub', (select id::text from auth.users order by created_at limit 1), true);
select set_config('test.backup_owner', current_setting('request.jwt.claim.sub'), true);
set local role authenticated;
select public.set_training_backup_consent(false,false);
do $$ begin
  begin
    insert into public.account_training_backups(user_id,device_id,payload)
    values(auth.uid(),'11111111-1111-4111-8111-111111111144',jsonb_build_object('ownerID',auth.uid(),'version',1,'records','{}'::jsonb));
    raise exception 'Upload without consent succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
select public.set_training_backup_consent(true,false);
insert into public.account_training_backups(user_id,device_id,payload)
values(auth.uid(),'11111111-1111-4111-8111-111111111144',jsonb_build_object('ownerID',auth.uid(),'version',1,'records','{}'::jsonb));
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222144',true);
do $$ begin
  if exists(select 1 from public.account_training_backups where device_id='11111111-1111-4111-8111-111111111144') then raise exception 'Cross-account read leaked'; end if;
  if exists(select 1 from public.training_backup_consent where user_id=current_setting('test.backup_owner')::uuid) then raise exception 'Cross-account consent leaked'; end if;
  begin
    insert into public.account_training_backups(user_id,device_id,payload)
    values(current_setting('test.backup_owner')::uuid,'33333333-3333-4333-8333-333333333144',jsonb_build_object('ownerID',current_setting('test.backup_owner'),'version',1,'records','{}'::jsonb));
    raise exception 'Cross-account insert succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('test.backup_owner'),true);
select public.set_training_backup_consent(false,true);
do $$ begin
  if exists(select 1 from public.account_training_backups where user_id=auth.uid()) then raise exception 'Deletion left backup rows'; end if;
  begin
    insert into public.account_training_backups(user_id,device_id,payload)
    values(auth.uid(),'44444444-4444-4444-8444-444444444144',jsonb_build_object('ownerID',auth.uid(),'version',1,'records','{}'::jsonb));
    raise exception 'Another device could recreate a deleted backup';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
