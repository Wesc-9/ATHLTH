-- Privacy: athlete-controlled withdrawal of minimal linked-workout evidence.
-- This removes the copied metadata, not the original workout or group-approved
-- aggregate competition points; deletion is server-authorized by auth.uid().
create or replace function private.arena_unshare_evidence_impl(p_evidence uuid)
returns boolean language plpgsql security definer
set search_path=pg_catalog,public,private as $$
declare
 v_actor uuid := (select auth.uid());
 v_deleted integer;
begin
 if v_actor is null then
   raise exception 'Authentication required';
 end if;
 delete from public.arena_workout_evidence
 where id=p_evidence and user_id=v_actor;
 get diagnostics v_deleted = row_count;
 return v_deleted=1;
end;$$;
create or replace function public.arena_unshare_evidence(p_evidence uuid)
returns boolean language sql security invoker
set search_path=pg_catalog,public,private as $$
 select private.arena_unshare_evidence_impl(p_evidence);
$$;
revoke all on function private.arena_unshare_evidence_impl(uuid) from public,anon;
revoke all on function public.arena_unshare_evidence(uuid) from public,anon;
grant execute on function private.arena_unshare_evidence_impl(uuid) to authenticated;
grant execute on function public.arena_unshare_evidence(uuid) to authenticated;
