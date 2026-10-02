-- No backup writes without a recorded, current opt-in. Legacy clients fail closed.
create table public.training_backup_consent (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  policy_version integer not null default 1 check (policy_version = 1),
  changed_at timestamptz not null default now()
);
alter table public.training_backup_consent enable row level security;
revoke all on public.training_backup_consent from public, anon;
grant select, insert, update on public.training_backup_consent to authenticated;
create policy consent_read on public.training_backup_consent for select to authenticated using ((select auth.uid()) = user_id);
create policy consent_insert on public.training_backup_consent for insert to authenticated with check ((select auth.uid()) = user_id);
create policy consent_update on public.training_backup_consent for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create function public.set_training_backup_consent(p_enabled boolean, p_delete boolean default false)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if p_delete and p_enabled then raise exception 'Deletion must revoke consent'; end if;
  insert into public.training_backup_consent(user_id,enabled,policy_version,changed_at)
    values(auth.uid(),p_enabled,1,now())
    on conflict(user_id) do update set enabled=excluded.enabled, policy_version=1, changed_at=now();
  -- The row lock above serializes this transaction with all backup writes.
  if p_delete then delete from public.account_training_backups where user_id=auth.uid(); end if;
end;
$$;
revoke all on function public.set_training_backup_consent(boolean,boolean) from public, anon;
grant execute on function public.set_training_backup_consent(boolean,boolean) to authenticated;

create function public.require_training_backup_consent()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare allowed boolean;
begin
  if new.user_id is distinct from auth.uid() then raise exception 'Not your backup' using errcode='42501'; end if;
  select enabled into allowed from public.training_backup_consent where user_id=new.user_id for update;
  if allowed is distinct from true then raise exception 'Cloud backup consent required' using errcode='42501'; end if;
  return new;
end;
$$;
revoke all on function public.require_training_backup_consent() from public, anon;
grant execute on function public.require_training_backup_consent() to authenticated;
create trigger require_backup_consent before insert or update on public.account_training_backups
  for each row execute function public.require_training_backup_consent();
