alter table public.social_challenges add column if not exists invitation_days integer not null default 3;
alter table public.social_challenges drop constraint if exists social_challenge_invitation_days_check;
alter table public.social_challenges add constraint social_challenge_invitation_days_check check(invitation_days between 1 and 30);

create or replace function private.athlth_duel_reply_deadline()
returns trigger language plpgsql set search_path='' as $fn$
declare days integer; status text;
begin
 if old.state='invited' and new.state='accepted' then
   select c.invitation_days,c.status into days,status
   from public.social_challenges c where c.id=new.challenge_id;
   if status not in ('invited','upcoming') or
      old.invited_at+make_interval(days=>coalesce(days,3))<=clock_timestamp() then
      raise exception 'Duel invitation has expired';
   end if;
 end if;
 return new;
end;$fn$;
drop trigger if exists athlth_duel_reply_deadline on public.social_challenge_participants;
create trigger athlth_duel_reply_deadline
before update on public.social_challenge_participants
for each row execute function private.athlth_duel_reply_deadline();

create or replace function public.athlth_duel_set_reply_days(
 p_challenge uuid,p_days integer)
returns void language plpgsql security definer set search_path='' as $fn$
begin
 if auth.uid() is null or p_days not between 1 and 30
 then raise exception 'Invalid reply deadline'; end if;
 update public.social_challenges c set invitation_days=p_days
 where c.id=p_challenge and c.creator_id=auth.uid()
  and c.status in ('invited','upcoming')
  and not exists(select 1 from public.social_challenge_participants p
    where p.challenge_id=c.id and p.state='accepted' and p.user_id<>auth.uid());
 if not found then raise exception 'Cannot change invitation deadline'; end if;
end;$fn$;
revoke all on function public.athlth_duel_set_reply_days(uuid,integer) from public,anon;
grant execute on function public.athlth_duel_set_reply_days(uuid,integer) to authenticated;

create or replace function private.athlth_duel_expire_invitations()
returns integer language plpgsql security definer set search_path='' as $fn$
declare v_count integer:=0; r record;
begin
 for r in select distinct c.id from public.social_challenges c
  join public.social_challenge_participants p on p.challenge_id=c.id
  where c.status in ('invited','upcoming') and p.state='invited'
    and p.invited_at+make_interval(days=>c.invitation_days)<=clock_timestamp()
  order by c.id limit 250
 loop
   perform 1 from public.social_challenges
     where id=r.id and status in ('invited','upcoming') for update;
   if not found then continue; end if;
   update public.social_challenge_participants p
     set state='declined',responded_at=clock_timestamp()
     from public.social_challenges c
     where p.challenge_id=r.id and c.id=r.id and p.state='invited'
      and p.invited_at+make_interval(days=>c.invitation_days)<=clock_timestamp();
   if found then
     update public.social_challenges set status='cancelled',updated_at=clock_timestamp()
       where id=r.id and status in ('invited','upcoming');
     v_count:=v_count+1;
   end if;
 end loop;
 return v_count;
end;$fn$;
revoke all on function private.athlth_duel_expire_invitations() from public,anon,authenticated;
select cron.schedule('athlth-duel-expire-invitations','* * * * *',
 'select private.athlth_duel_expire_invitations()');