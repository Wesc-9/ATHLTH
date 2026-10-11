-- Arena lifecycle/privacy regression checks, run against disposable Supabase.
begin;
do $$
declare v_policy text;
begin
 if has_function_privilege(
   'anon',
   'public.arena_change_invitation(uuid,uuid,uuid)'::regprocedure,
   'EXECUTE'
 ) or has_function_privilege(
   'anon',
   'public.arena_refresh_my_deadlines()'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Anonymous Arena lifecycle RPC access is not allowed';
 end if;
 if not has_function_privilege(
   'authenticated',
   'public.arena_change_invitation(uuid,uuid,uuid)'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Authenticated organizer invitation change unavailable';
 end if;
 select with_check into v_policy
 from pg_policies where schemaname='public'
   and tablename='arena_series' and policyname='arena_series_insert';
 if v_policy not like '%can_manage_community_group%' then
   raise exception 'Club series bypasses administrator insert guard';
 end if;
 select with_check into v_policy
 from pg_policies where schemaname='public'
   and tablename='arena_series_members' and policyname='arena_members_invite';
 if v_policy not like '%community_group_members%' then
   raise exception 'Club invitation bypasses membership check';
 end if;
 if not exists (
   select 1 from information_schema.columns
   where table_schema='public' and table_name='arena_series'
   and column_name='completion_reason'
 ) then
   raise exception 'Missing result completion distinction';
 end if;
 if not exists (
   select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='arena_finalize_due_all'
 ) then
   raise exception 'Missing deadline finalizer';
 end if;
 if not exists (
   select 1 from cron.job
   where jobname='athlth-arena-complete-due-series' and active
 ) then
   raise exception 'Arena automatic deadline job missing';
 end if;
 if not exists (
   select 1 from pg_trigger
   where tgrelid='public.arena_series_members'::regclass
     and tgname='arena_notify_invitation_response' and tgenabled='O'
 ) then
   raise exception 'Invitation response notification trigger is missing';
 end if;
end $$;
rollback;
