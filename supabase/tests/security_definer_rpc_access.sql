-- Safeguard exposed SECURITY DEFINER RPCs against anonymous execution.
-- Run on the disposable local Supabase database, never as production DDL.
-- SECURITY DEFINER is intentional for authenticated operations that enforce
-- auth.uid(), membership and owner checks in their function bodies.
begin;

do $$
declare
  exposed_count integer;
  total_count integer;
begin
  select
    count(*) filter (
      where has_function_privilege('anon', p.oid, 'EXECUTE')
    ),
    count(*)
  into exposed_count, total_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prosecdef;

  if total_count = 0 then
    raise exception 'Expected secured RPC functions to exist';
  end if;

  if exposed_count <> 0 then
    raise exception '% SECURITY DEFINER functions became executable by anon',
      exposed_count;
  end if;

  -- These tables are intentionally service-role-only.
  -- RLS with zero policies should never become accidentally disabled.
  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private'
      and c.relname = 'ai_request_budgets'
      and c.relrowsecurity
  ) then
    raise exception 'AI request budgets must remain RLS-protected';
  end if;

  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'public_media_moderation_events'
      and c.relrowsecurity
  ) then
    raise exception 'Moderation audit events must remain RLS-protected';
  end if;
end $$;

set local role anon;
do $$
begin
  if has_function_privilege(
    'public.register_notification_device(text,text,text,text,text,text)',
    'EXECUTE'
  ) or has_function_privilege(
    'public.record_community_group_workout(uuid,timestamp with time zone)',
    'EXECUTE'
  ) or has_function_privilege(
    'public.ensure_official_weekly_challenge_horizon(integer)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous users gained access to authenticated RPCs';
  end if;
end $$;
reset role;

set local role authenticated;
do $$
begin
  if not has_function_privilege(
    'public.register_notification_device(text,text,text,text,text,text)',
    'EXECUTE'
  ) or not has_function_privilege(
    'public.respond_to_direct_message_request(uuid,boolean)',
    'EXECUTE'
  ) or not has_function_privilege(
    'public.ensure_official_weekly_challenge_horizon(integer)',
    'EXECUTE'
  ) then
    raise exception 'Required authenticated client RPC access was lost';
  end if;
end $$;
reset role;

rollback;
