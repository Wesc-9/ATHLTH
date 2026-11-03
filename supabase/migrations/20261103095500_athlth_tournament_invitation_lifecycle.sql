-- Keep stalled invitations recoverable without rewriting accepted responses.
-- A cancelled tournament remains in members' history instead of vanishing.
create or replace function public.athlth_tournament_withdraw_invite(
    p_tournament uuid, p_athlete uuid
) returns void
language plpgsql security definer set search_path=''
as $$
declare
    v_owner uuid := auth.uid();
    v_t public.athlth_tournaments%rowtype;
begin
    if v_owner is null then raise exception 'Sign in required'; end if;
    select * into v_t from public.athlth_tournaments
    where id=p_tournament for update;
    if not found or v_t.owner_id<>v_owner or v_t.status<>'inviting' or
       p_athlete=v_owner then
        raise exception 'Only the organizer may withdraw an unanswered invitation';
    end if;
    delete from public.athlth_tournament_entries
    where tournament_id=p_tournament and user_id=p_athlete
      and response in ('invited','declined');
    if not found then raise exception 'Invitation cannot be withdrawn'; end if;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event,info
    ) values(
        p_tournament,v_owner,'invitation_withdrawn',
        jsonb_build_object('athlete',p_athlete)
    );
end;
$$;
revoke all on function public.athlth_tournament_withdraw_invite(uuid,uuid)
from public,anon;
grant execute on function public.athlth_tournament_withdraw_invite(uuid,uuid)
to authenticated;

create or replace function public.athlth_tournament_cancel(p_tournament uuid)
returns void
language plpgsql security definer set search_path=''
as $$
declare
    v_owner uuid := auth.uid();
    v_status text;
begin
    if v_owner is null then raise exception 'Sign in required'; end if;
    select status into v_status from public.athlth_tournaments
    where id=p_tournament and owner_id=v_owner for update;
    if v_status is distinct from 'inviting' then
        raise exception 'Only an unstarted tournament may be cancelled';
    end if;
    update public.athlth_tournaments
    set status='cancelled',completed_at=now()
    where id=p_tournament and owner_id=v_owner;
    insert into public.athlth_tournament_audit(tournament_id,actor_id,event)
    values(p_tournament,v_owner,'cancelled');
end;
$$;
revoke all on function public.athlth_tournament_cancel(uuid) from public,anon;
grant execute on function public.athlth_tournament_cancel(uuid) to authenticated;
