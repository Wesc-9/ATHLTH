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
   where table_schema='public'
     and table_name='ghost_race_challenges'
     and column_name='source_kind'
 ) then
   raise exception 'Live Ghost course origin must distinguish past workouts from planned routes';
 end if;
 if not exists (
   select 1 from pg_constraint
   where conrelid='public.ghost_race_challenges'::regclass
     and conname='ghost_race_source_kind_check' and convalidated
 ) then
   raise exception 'Live Ghost course origins require a validated constraint';
 end if;
 if has_table_privilege('anon','public.ghost_race_challenges','SELECT')
    or has_table_privilege('anon','public.ghost_race_challenges','INSERT') then
   raise exception 'Anonymous actors cannot view or create Live Ghost challenges';
 end if;
 -- Linked Live Ghost results must be restricted to accepted active
 -- 1v1 participants and may never bypass the existing friend policy.
 if not exists (
   select 1 from information_schema.columns
   where table_schema='public'
     and table_name='ghost_race_challenges'
     and column_name='arena_round_id'
 ) then
   raise exception 'Live Ghost to Arena round provenance is missing';
 end if;
 if not exists (
   select 1 from pg_policies
   where schemaname='public'
     and tablename='ghost_race_challenges'
     and policyname='friends can send ghost races'
     and with_check like '%can_send_ghost_race%'
     and with_check like '%ghost_race_arena_link_allowed%'
 ) then
   raise exception 'Live Ghost invite must validate friend/privacy and Arena membership';
 end if;
 if not exists (
   select 1 from pg_policies
   where schemaname='public'
     and tablename='ghost_race_challenges'
     and policyname='friends can send ghost races'
     and with_check like '%ghost_race_arena_link_allowed%'
     and with_check like '%ghost_race_arena_route_compatible%'
 ) then
   raise exception 'Linked Live Ghost requires both membership and route compatibility';
 end if;
 if private.ghost_race_arena_route_compatible(
      gen_random_uuid(), 'planned_route', 5000.0
    ) or private.ghost_race_arena_route_compatible(
      gen_random_uuid(), 'previous_workout', 5000.0
    ) then
   raise exception 'Unrelated Live Ghost route attribution incorrectly permitted';
 end if;
 if has_table_privilege('anon','public.ghost_race_challenges','SELECT')
    or has_table_privilege('anon','public.ghost_race_challenges','INSERT') then
   raise exception 'Linked Live Ghost races leaked to anonymous users';
 end if;
 if private.ghost_race_arena_link_allowed(
     gen_random_uuid(),gen_random_uuid(),gen_random_uuid()
   ) then
   raise exception 'Unrelated Live Ghost actors may link arbitrary Arena rounds';
 end if;
 if not exists (
   select 1 from pg_trigger
   where tgrelid='public.live_ghost_race_participants'::regclass
     and tgname='live_ghost_finish_once_before_update'
     and tgenabled='O'
 ) then
   raise exception 'Live Ghost must preserve the first submitted finish';
 end if;
 if not exists (
   select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='live_ghost_finish_once_guard'
 ) then
   raise exception 'Live Ghost finish validation function missing';
 end if;
 -- A relay plan can be read by authorized series participants but can only
 -- be changed through the organizer-only draft RPC.
 if not (select relrowsecurity from pg_class
         where oid='public.arena_series_relay_legs'::regclass) then
   raise exception 'Relay stage plan must have RLS';
 end if;
 if has_table_privilege('anon','public.arena_series_relay_legs','SELECT')
    or has_table_privilege('anon','public.arena_series_relay_legs','INSERT')
    or has_table_privilege('authenticated','public.arena_series_relay_legs','INSERT')
    or has_table_privilege('authenticated','public.arena_series_relay_legs','UPDATE')
    or has_table_privilege('authenticated','public.arena_series_relay_legs','DELETE') then
   raise exception 'Relay plans allow unsafe direct writes';
 end if;
 if not exists (
   select 1 from pg_policies where schemaname='public'
    and tablename='arena_series_relay_legs'
    and policyname='arena_relay_legs_read'
    and qual like '%arena_can_access%'
 ) then
   raise exception 'Relay plan read access bypasses Arena membership';
 end if;
 if not has_function_privilege('authenticated',
    'public.arena_save_relay_lineup(uuid,uuid,uuid[],uuid[])'::regprocedure,'EXECUTE')
    or has_function_privilege('anon',
    'public.arena_save_relay_lineup(uuid,uuid,uuid[],uuid[])'::regprocedure,'EXECUTE') then
   raise exception 'Relay lineup RPC is not authenticated only';
 end if;
 if has_function_privilege('authenticated',
    'private.arena_clear_relay_on_roster_change()'::regprocedure,'EXECUTE') then
   raise exception 'Relay reset trigger must not be publicly invocable';
 end if;
 if not exists (
    select 1 from pg_trigger where
      tgrelid='public.arena_series_team_assignments'::regclass
      and tgname='arena_clear_relay_on_roster_change' and tgenabled='O'
 ) then
    raise exception 'Team changes do not clear stale relay plans';
 end if;
 -- Team mode is an optional read-only overlay. Only the organizer
 -- can replace all assignments through the draft-only RPC.
 if not (select relrowsecurity from pg_class
         where oid='public.arena_series_team_assignments'::regclass) then
   raise exception 'Arena team rosters must have RLS enabled';
 end if;
 if has_table_privilege('anon','public.arena_series_team_assignments','SELECT')
    or has_table_privilege('anon','public.arena_series_team_assignments','INSERT')
    or has_table_privilege('authenticated','public.arena_series_team_assignments','INSERT')
    or has_table_privilege('authenticated','public.arena_series_team_assignments','UPDATE')
    or has_table_privilege('authenticated','public.arena_series_team_assignments','DELETE') then
   raise exception 'Arena team assignments allow unsafe direct writes';
 end if;
 if not exists (
   select 1 from pg_policies where schemaname='public'
     and tablename='arena_series_team_assignments'
     and policyname='arena_team_roster_read'
     and qual like '%arena_can_access%'
 ) then
   raise exception 'Arena team rosters have no participant-only read policy';
 end if;
 if not has_function_privilege(
   'authenticated',
   'public.arena_save_team_lineup(uuid,uuid[],uuid[])'::regprocedure,
   'EXECUTE'
 ) or has_function_privilege(
   'anon',
   'public.arena_save_team_lineup(uuid,uuid[],uuid[])'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Arena team setup RPC privileges are incorrect';
 end if;
 -- Relay timing is opt-in per assigned athlete; clients may not
 -- write another member's time directly or grant points.
 if not (select relrowsecurity from pg_class
         where oid='public.arena_relay_leg_reports'::regclass) then
   raise exception 'Arena relay leg reporting RLS disabled';
 end if;
 if has_table_privilege('anon','public.arena_relay_leg_reports','SELECT')
    or has_table_privilege('anon','public.arena_relay_leg_reports','INSERT')
    or has_table_privilege('authenticated','public.arena_relay_leg_reports','INSERT')
    or has_table_privilege('authenticated','public.arena_relay_leg_reports','UPDATE')
    or has_table_privilege('authenticated','public.arena_relay_leg_reports','DELETE')
 then
   raise exception 'Arena relay report table direct privileges are too broad';
 end if;
 if not has_function_privilege(
   'authenticated',
   'public.arena_report_relay_leg(uuid,uuid,numeric)'::regprocedure,
   'EXECUTE'
 ) or has_function_privilege(
   'anon',
   'public.arena_report_relay_leg(uuid,uuid,numeric)'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Arena relay time submission RPC privileges are incorrect';
 end if;
 if not exists (
   select 1 from pg_policies
   where schemaname='public' and tablename='arena_relay_leg_reports'
     and policyname='arena_relay_reports_read'
     and qual like '%arena_can_access%'
 ) then
   raise exception 'Arena relay leg report reads are not protected by series membership';
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
 -- Relay reminders are a user-triggered inbox notification, not a
 -- client-writeable baton state or an automatic scoring surface.
 if not exists (
   select 1 from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public'
     and p.proname='arena_notify_next_relay_runner'
 ) then
   raise exception 'Opt-in relay runner notification RPC is missing';
 end if;
 if has_function_privilege(
   'anon',
   'public.arena_notify_next_relay_runner(uuid,uuid)'::regprocedure,
   'EXECUTE'
 ) or not has_function_privilege(
   'authenticated',
   'public.arena_notify_next_relay_runner(uuid,uuid)'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Relay reminder RPC must require an authenticated runner';
 end if;
 if has_table_privilege(
   'authenticated',
   'public.arena_relay_next_runner_notices',
   'INSERT'
 ) or has_table_privilege(
   'anon',
   'public.arena_relay_next_runner_notices',
   'SELECT'
 ) or not (
   select relrowsecurity from pg_class
   where oid='public.arena_relay_next_runner_notices'::regclass
 ) then
   raise exception 'Relay reminder dedup state must remain server-private';
 end if;
 -- Arena 2.0 route evidence must remain participant-reported and private.
 if not exists (
   select 1 from information_schema.columns
   where table_schema='public' and table_name='arena_workout_evidence'
     and column_name='reported_route_match_percent'
 ) or not exists (
   select 1 from information_schema.columns
   where table_schema='public' and table_name='arena_round_proposals'
     and column_name='route_snapshot'
 ) then
   raise exception 'Arena route evidence fields are missing';
 end if;
 if has_function_privilege(
   'anon',
   'public.arena_share_route_evidence(uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,numeric)'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Anonymous route evidence submission is forbidden';
 end if;
 if not has_function_privilege(
   'authenticated',
   'public.arena_share_route_evidence(uuid,uuid,timestamptz,timestamptz,numeric,numeric,numeric,numeric,numeric)'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Authenticated route evidence RPC is missing';
 end if;
 if not exists (
   select 1 from pg_constraint
   where conrelid='public.arena_round_proposals'::regclass
     and conname='arena_round_target_configuration_check' and convalidated
 ) then
   raise exception 'Arena structured round rules constraint is missing';
 end if;
 if not (select relrowsecurity from pg_class
         where oid='public.arena_workout_evidence'::regclass) then
   raise exception 'Arena evidence row-level security disabled';
 end if;
 if not private.arena_route_snapshot_valid(
   '{"title":"Valid route","distanceKilometers":5,"coordinates":[{"latitude":59.1,"longitude":10.1},{"latitude":59.2,"longitude":10.2}]}'::jsonb,
   5000
 ) then
   raise exception 'Valid Arena route snapshot rejected';
 end if;
 if private.arena_route_snapshot_valid(
   '{"title":"Invalid route","distanceKilometers":5,"coordinates":[{"latitude":123,"longitude":10},{"latitude":59.2,"longitude":10.2}]}'::jsonb,
   5000
 ) or private.arena_route_snapshot_valid(
   '{"title":"Missing point","distanceKilometers":5,"coordinates":[{"latitude":59,"longitude":10}]}'::jsonb,
   5000
 ) then
   raise exception 'Malformed Arena route was accepted';
 end if;
 -- Relay correction history stays private, append-only from the app
 -- and is populated only by the authenticated leg-report RPC trigger.
 if to_regclass('public.arena_relay_leg_history') is null then
   raise exception 'Relay report correction history table is missing';
 end if;
 if has_table_privilege('anon','public.arena_relay_leg_history','SELECT')
   or has_table_privilege('authenticated','public.arena_relay_leg_history','INSERT')
   or has_table_privilege('authenticated','public.arena_relay_leg_history','UPDATE')
   or has_table_privilege('authenticated','public.arena_relay_leg_history','DELETE') then
   raise exception 'Relay time history must be private and not client-editable';
 end if;
 if not (select relrowsecurity from pg_class
         where oid='public.arena_relay_leg_history'::regclass) then
   raise exception 'Relay time history RLS was disabled';
 end if;
 if not exists (
   select 1 from pg_policies
   where schemaname='public'
     and tablename='arena_relay_leg_history'
     and policyname='arena_relay_history_read'
     and qual like '%arena_can_access%'
 ) then
   raise exception 'Relay time history must use the existing Arena membership check';
 end if;
 if not exists (
   select 1 from pg_trigger
   where tgrelid='public.arena_relay_leg_reports'::regclass
     and tgname='arena_track_relay_leg_change'
     and tgenabled='O'
 ) then
   raise exception 'Relay report changes are not being audited';
 end if;
 if has_function_privilege(
   'authenticated',
   'private.arena_append_relay_leg_history()'::regprocedure,
   'EXECUTE'
 ) then
   raise exception 'Clients must not call the private relay history trigger';
 end if;
 if pg_get_functiondef('public.arena_report_relay_leg(uuid,uuid,numeric)'::regprocedure)
      not like '%arena_round_results%'
    or pg_get_functiondef('public.arena_report_relay_leg(uuid,uuid,numeric)'::regprocedure)
      not like '%pending%approved%'
 then
   raise exception 'Relay times must be frozen while a round result is pending or approved';
 end if;
 if has_table_privilege('authenticated','public.arena_relay_leg_reports','UPDATE')
    or has_table_privilege('authenticated','public.arena_relay_leg_reports','DELETE') then
   raise exception 'Clients must not circumvent relay vote freeze using direct updates';
 end if;

end $$;
rollback;
