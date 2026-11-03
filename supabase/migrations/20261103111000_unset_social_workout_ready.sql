-- Permit an athlete to undo Ready only before any countdown is scheduled.
-- Match schedule_social_workout_start's lock order (session, then participant)
-- to prevent races between Unready and a synchronized start.
create or replace function public.unset_social_workout_ready(p_session_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = 'pg_catalog', 'public'
as $function$
declare
    current_session public.social_workout_sessions%rowtype;
    affected_count integer;
begin
    if (select auth.uid()) is null then
        raise exception 'Authentication required';
    end if;

    select * into current_session
    from public.social_workout_sessions
    where id = p_session_id
    for update;

    if current_session.id is null
       or current_session.status <> 'active'
       or current_session.workout_phase <> 'planned'
       or current_session.coordinated_start_at is not null
       or coalesce(current_session.invite_payload ->> 'startIndependently', 'false') = 'true'
    then
        raise exception 'Ready can only be undone before the workout starts';
    end if;

    update public.social_workout_participants
    set ready_at = null,
        capture_device = null
    where session_id = p_session_id
      and user_id = (select auth.uid())
      and state in ('creator', 'accepted')
      and workout_started_at is null
      and workout_finished_at is null;

    get diagnostics affected_count = row_count;
    if affected_count <> 1 then
        raise exception 'You are not an active participant in this workout';
    end if;

    return true;
end;
$function$;

revoke all on function public.unset_social_workout_ready(uuid) from public, anon;
grant execute on function public.unset_social_workout_ready(uuid) to authenticated;
