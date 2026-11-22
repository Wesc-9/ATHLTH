alter table public.athlth_tournaments add column if not exists invitation_days integer not null default 3;
alter table public.athlth_tournaments add column if not exists unanswered_policy text not null default 'cancel';
alter table public.athlth_tournaments add column if not exists replacement_until timestamptz;
alter table public.athlth_tournaments add column if not exists allow_feed_post boolean not null default true;
alter table public.athlth_tournaments add column if not exists feed_published_at timestamptz;
alter table public.athlth_tournaments drop constraint if exists athlth_invitation_days_check;
alter table public.athlth_tournaments add constraint athlth_invitation_days_check check(invitation_days between 1 and 30);
alter table public.athlth_tournaments drop constraint if exists athlth_unanswered_policy_check;
alter table public.athlth_tournaments add constraint athlth_unanswered_policy_check check(unanswered_policy in ('cancel','continue','replace'));
alter table public.athlth_tournament_entries add column if not exists invited_at timestamptz;
alter table public.athlth_tournament_entries add column if not exists expires_at timestamptz;
update public.athlth_tournament_entries e set invited_at=coalesce(e.invited_at,t.created_at),expires_at=coalesce(e.expires_at,t.created_at+make_interval(days=>t.invitation_days)) from public.athlth_tournaments t where t.id=e.tournament_id and e.response='invited' and (e.invited_at is null or e.expires_at is null);
alter table public.athlth_tournament_entries drop constraint if exists athlth_tournament_entries_response_check;
alter table public.athlth_tournament_entries add constraint athlth_tournament_entries_response_check check(response in ('invited','accepted','declined','expired'));
create or replace function private.athlth_competition_entry_invitation_dates()
returns trigger language plpgsql set search_path='' as $fn$
declare days integer;
begin
 if new.response='invited' then
   select t.invitation_days into days from public.athlth_tournaments t
     where t.id=new.tournament_id;
   new.invited_at:=coalesce(new.invited_at,clock_timestamp());
   new.expires_at:=coalesce(new.expires_at,
       new.invited_at+make_interval(days=>coalesce(days,3)));
 end if;
 return new;
end;$fn$;
drop trigger if exists athlth_competition_entry_invitation_dates
on public.athlth_tournament_entries;
create trigger athlth_competition_entry_invitation_dates
before insert on public.athlth_tournament_entries
for each row execute function private.athlth_competition_entry_invitation_dates();

create or replace function private.athlth_competition_expire_invitations()
returns integer language plpgsql security definer set search_path='' as $fn$
declare t record; expired_count integer; accepted_count integer;
 pending_count integer; processed integer:=0; now_time timestamptz:=clock_timestamp();
begin
 for t in select x.* from public.athlth_tournaments x
   where x.status='inviting' and x.competition_settings_applied
     and (exists(select 1 from public.athlth_tournament_entries e
       where e.tournament_id=x.id and e.response='invited'
         and e.expires_at<=now_time)
       or (x.unanswered_policy='replace' and x.replacement_until<=now_time)
       or not exists(select 1 from public.athlth_tournament_entries e
           where e.tournament_id=x.id and e.response='invited'))
   order by x.created_at limit 250
 loop
   -- Same row lock as all start/respond operations. Never cancel an active event.
   perform 1 from public.athlth_tournaments x where x.id=t.id for update;
   if not exists(select 1 from public.athlth_tournaments x
     where x.id=t.id and x.status='inviting') then continue; end if;
   update public.athlth_tournament_entries e
    set response='expired',responded_at=now_time
    where e.tournament_id=t.id and e.response='invited'
      and e.expires_at<=now_time;
   get diagnostics expired_count=row_count;
   if expired_count>0 then
     insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
     values(t.id,t.owner_id,'invitation_expired',
       jsonb_build_object('count',expired_count));
   end if;
   select count(*) into accepted_count from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.response='accepted' and e.removed_at is null;
   select count(*) into pending_count from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.response='invited' and e.removed_at is null;
   if pending_count=0 and accepted_count<=1 then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'cancelled',jsonb_build_object('reason','no_acceptances'));
      processed:=processed+1;
   elsif expired_count>0 and t.unanswered_policy='cancel' then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'cancelled',jsonb_build_object('reason','invitation_expired'));
      processed:=processed+1;
   elsif expired_count>0 and t.unanswered_policy='replace' and t.replacement_until is null then
      update public.athlth_tournaments set replacement_until=
        now_time+make_interval(days=>t.invitation_days) where id=t.id;
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'replacement_window_opened',
        jsonb_build_object('days',t.invitation_days));
      processed:=processed+1;
   elsif pending_count=0 and t.unanswered_policy='continue' and
         accepted_count<(case when t.format='cup' then 4 else 2 end) then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      processed:=processed+1;
   elsif t.unanswered_policy='replace' and t.replacement_until<=now_time then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'cancelled',jsonb_build_object('reason','replacement_deadline'));
      processed:=processed+1;
   end if;
 end loop;
 return processed;
end;$fn$;
revoke all on function private.athlth_competition_expire_invitations() from public,anon,authenticated;
select cron.schedule('athlth-competition-expire-invitations','* * * * *',
 'select private.athlth_competition_expire_invitations()');