alter table public.athlth_tournaments
 add column if not exists replacement_resolved boolean not null default false;
CREATE OR REPLACE FUNCTION private.athlth_competition_expire_invitations()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t record; expired_count integer; declined_count integer; accepted_count integer;
 pending_count integer; processed integer:=0; now_time timestamptz:=clock_timestamp();
begin
 for t in select x.* from public.athlth_tournaments x
   where x.status='inviting' and x.competition_settings_applied
     and (exists(select 1 from public.athlth_tournament_entries e
       where e.tournament_id=x.id and e.response='invited'
         and e.expires_at<=now_time)
       or (x.unanswered_policy='replace' and x.replacement_until<=now_time)
       or exists(select 1 from public.athlth_tournament_entries refused
          where refused.tournament_id=x.id and refused.response='declined')
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
   select count(*) into declined_count from public.athlth_tournament_entries e
     where e.tournament_id=t.id and e.response in ('declined','expired');
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
   elsif declined_count>0 and t.unanswered_policy='cancel' then
      update public.athlth_tournaments set status='cancelled',completed_at=now_time
        where id=t.id and status='inviting';
      insert into public.athlth_tournament_audit(tournament_id,actor_id,event,info)
      values(t.id,t.owner_id,'cancelled',jsonb_build_object('reason','invitation_expired'));
      processed:=processed+1;
   elsif declined_count>0 and t.unanswered_policy='replace'
      and t.replacement_until is null and not t.replacement_resolved then
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
end;$function$
;
CREATE OR REPLACE FUNCTION public.athlth_tournament_finish_replacement(p_tournament uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t public.athlth_tournaments%rowtype; n integer;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 select * into t from public.athlth_tournaments where id=p_tournament for update;
 if not found or t.owner_id<>auth.uid() or t.status<>'inviting'
   or t.unanswered_policy<>'replace' or t.replacement_until is null then
   raise exception 'Only the organizer can close an active replacement window';
 end if;
 if exists(select 1 from public.athlth_tournament_entries e
    where e.tournament_id=t.id and e.response='invited') then
   raise exception 'There are still pending invitations'; end if;
 select count(*) into n from public.athlth_tournament_entries e
  where e.tournament_id=t.id and e.response='accepted'
    and e.removed_at is null;
 if n<(case when t.format='cup' then 4 else 2 end) then
  raise exception 'Not enough athletes accepted'; end if;
 update public.athlth_tournaments set replacement_until=null,
    replacement_resolved=true where id=t.id;
 insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
 values(t.id,auth.uid(),'replacement_window_closed');
end;$function$
;