-- Run ONLY after account-owned plan sync migration is applied to staging.
-- Uses one existing test account, selects no personal data, and rolls back.
begin;
do $$
declare account_id uuid;
begin
  select id into account_id from auth.users order by created_at limit 1;
  if account_id is null then
    raise exception 'Test requires an existing test account';
  end if;
  perform set_config('request.jwt.claim.sub', account_id::text, true);
  perform set_config('test.plan_sync_owner', account_id::text, true);
end $$;
set local role authenticated;

-- No separate consent row must be necessary for a new account.
delete from public.studio_plan_sync_consents where user_id = auth.uid();
insert into public.studio_plan_documents(user_id,plan_id,revision,body_base64)
values(auth.uid(),'66111111-1111-4111-8111-111111111111',1,'e30=');
do $$ begin
  if not exists (
    select 1 from public.studio_plan_documents
    where user_id=auth.uid() and plan_id='66111111-1111-4111-8111-111111111111'
  ) then raise exception 'Owner cannot access account plan'; end if;
end $$;

-- Explicit historical opt-out must prevent new reads and writes.
insert into public.studio_plan_sync_consents(user_id,enabled)
values(auth.uid(),false)
on conflict(user_id) do update set enabled=false;
do $$ begin
  if exists (
    select 1 from public.studio_plan_documents
    where plan_id='66111111-1111-4111-8111-111111111111'
  ) then raise exception 'Legacy opt-out did not block reads'; end if;
  begin
    insert into public.studio_plan_documents(user_id,plan_id,revision,body_base64)
    values(auth.uid(),'66222222-2222-4222-8222-222222222222',1,'e30=');
    raise exception 'Legacy opt-out allowed new plan';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;

-- Simulate another signed-in account: no cross-account read or insert.
select set_config('request.jwt.claim.sub','66999999-9999-4999-8999-999999999999',true);
do $$ begin
  if exists (
    select 1 from public.studio_plan_documents
    where user_id=current_setting('test.plan_sync_owner')::uuid
  ) then raise exception 'Cross-account read leaked'; end if;
  begin
    insert into public.studio_plan_documents(user_id,plan_id,revision,body_base64)
    values(current_setting('test.plan_sync_owner')::uuid,
           '66333333-3333-4333-8333-333333333333',1,'e30=');
    raise exception 'Cross-account write succeeded';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;
rollback;
