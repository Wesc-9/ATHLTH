-- Harden Undo Ready for invited participants. The public RPC stays
-- SECURITY INVOKER. A narrowly-scoped function in the unexposed private
-- schema acquires the session lock also needed by non-organizers.
create or replace function private.unset_social_workout_ready_impl(p_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = 'pg_catalog', 'public', 'private'
as $function$
declare
    caller uuid := (select auth.uid());
    current_session public.social_workout_sessions%rowtype;
    affected_count integer;
begin
    if caller is null then
        raise exception 'Authentication required';
    end if;

    -- Do not reveal the state of a session the caller has not joined.
    if not exists (
        select 1 from public.social_workout_participants
        where session_id = p_session_id
          and user_id = caller
          and state in ('creator', 'accepted')
          and workout_started_at is null
          and workout_finished_at is null
    ) then
        raise exception 'You are not an active participant in this workout';
    end if;

    -- Same lock order as schedule_social_workout_start. Whichever commits
    -- first wins; Undo is never allowed after a countdown was scheduled.
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
      and user_id = caller
      and state in ('creator', 'accepted')
      and workout_started_at is null
      and workout_finished_at is null;

    get diagnostics affected_count = row_count;
    if affected_count <> 1 then
        raise exception 'Could not undo Ready for this participant';
    end if;

    return true;
end;
$function$;

revoke all on function private.unset_social_workout_ready_impl(uuid) from public, anon;
grant execute on function private.unset_social_workout_ready_impl(uuid) to authenticated;

create or replace function public.unset_social_workout_ready(p_session_id uuid)
returns boolean
language sql
security invoker
set search_path = 'pg_catalog', 'private'
as $function$
    select private.unset_social_workout_ready_impl(p_session_id);
$function$;

revoke all on function public.unset_social_workout_ready(uuid) from public, anon;
grant execute on function public.unset_social_workout_ready(uuid) to authenticated;
