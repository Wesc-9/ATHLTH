CREATE OR REPLACE FUNCTION public.athlth_tournament_respond(p_tournament uuid, p_accept boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user uuid := auth.uid();
    v_status text;
begin
    if v_user is null then raise exception 'Sign in required'; end if;
    select status into v_status from public.athlth_tournaments
    where id=p_tournament for update;
    if v_status is distinct from 'inviting' then
        raise exception 'Tournament invitations are closed';
    end if;
    update public.athlth_tournament_entries
       set response=case when p_accept then 'accepted' else 'declined' end,
           responded_at=now()
     where tournament_id=p_tournament and user_id=v_user
       and response='invited'
       and expires_at>clock_timestamp();
    if not found then raise exception 'No active invitation; the reply deadline may have passed'; end if;
    insert into public.athlth_tournament_audit(
        tournament_id,actor_id,event
    ) values(p_tournament,v_user,
        case when p_accept then 'invitation_accepted'
             else 'invitation_declined' end);
end;
$function$
