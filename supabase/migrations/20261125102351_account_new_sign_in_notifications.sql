-- Account-owner security notices share the existing private inbox/APNs pipeline.
do $migration$
declare previous_check text;
begin
 select pg_catalog.pg_get_constraintdef(c.oid) into previous_check
 from pg_catalog.pg_constraint c
 where c.conrelid='public.social_inbox_events'::pg_catalog.regclass
 and c.conname='social_inbox_events_kind_check';
 if previous_check is null or left(previous_check,7)<>'CHECK (' then
   raise exception 'Missing inbox kind constraint';
 end if;
 if position('account_new_sign_in' in previous_check)=0 then
   alter table public.social_inbox_events drop constraint social_inbox_events_kind_check;
   execute 'alter table public.social_inbox_events add constraint social_inbox_events_kind_check ' ||
     left(previous_check,length(previous_check)-1) || ' OR kind = ''account_new_sign_in'')';
 end if;
end $migration$;

create or replace function private.athlth_notify_new_account_session()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- Existing devices registering after upgrade are not fresh logins.
 if new.signed_in_at < now()-interval '15 minutes' or new.signed_in_at > now()+interval '1 minute' then return new; end if;
 -- Only a real current auth session, not a supplied device identifier, may produce a notice.
 if not exists(select 1 from auth.sessions s where s.id=new.session_id and s.user_id=new.user_id) then return new; end if;
 insert into public.social_inbox_events(recipient_id,actor_id,kind,title,message,entity_type,entity_id)
 values(new.user_id,null,'account_new_sign_in','New ATHLTH sign-in',
 'A new sign-in was registered for your account. If it was not you, review your signed-in devices in Account & Security.',
 'account_security',new.session_id);
 return new;
end; $$;
revoke all on function private.athlth_notify_new_account_session() from public,anon,authenticated;
drop trigger if exists athlth_new_account_session_notification on private.athlth_account_login_history;
create trigger athlth_new_account_session_notification
after insert on private.athlth_account_login_history
for each row execute function private.athlth_notify_new_account_session();
