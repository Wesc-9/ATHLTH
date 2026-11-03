-- Tournament activity/rule contract smoke checks; does not mutate user data.
do $$
declare
 v_count integer;
begin
 if not private.athlth_validate_activity_types(array['running','strength']) then
   raise exception 'Mixed sports should be valid';
 end if;
 if private.athlth_validate_activity_types(array['cycling','cycling']) or
    private.athlth_validate_activity_types(array['running','unrecognized']) or
    private.athlth_validate_activity_types(array[]::text[]) then
   raise exception 'Invalid activity selections should be rejected';
 end if;
 select count(distinct activity_type) into v_count
 from public.athlth_tournament_activity_templates where is_active;
 if v_count<6 then
   raise exception 'Missing competition activity presets';
 end if;
 if not (select relrowsecurity from pg_class
         where oid='public.athlth_tournament_rule_votes'::regclass)
    or not (select relrowsecurity from pg_class
            where oid='public.athlth_tournament_rule_proposals'::regclass)
    or not (select relrowsecurity from pg_class
            where oid='public.athlth_tournament_activity_templates'::regclass) then
    raise exception 'Sports or rule tables must have RLS';
 end if;
 if has_table_privilege('anon','public.athlth_tournament_rule_votes','SELECT')
    or has_table_privilege('authenticated','public.athlth_tournament_rule_votes','UPDATE')
    or has_table_privilege('authenticated','public.athlth_tournaments','UPDATE') then
    raise exception 'Unsafe direct write privilege';
 end if;
 if has_function_privilege('anon',
    'public.athlth_tournament_vote_rules(uuid)','EXECUTE') or
    has_function_privilege('anon',
    'public.athlth_tournament_create_with_rules(text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,timestamptz,timestamptz,boolean,text[],text,integer,integer)','EXECUTE') then
    raise exception 'Anonymous users must not manage tournament rules';
 end if;
 if has_function_privilege('authenticated',
    'public.athlth_tournament_create(text,text,uuid,uuid,integer,integer,uuid[],text[])','EXECUTE') or
    has_function_privilege('authenticated',
    'public.athlth_tournament_create_configured(text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,timestamptz,timestamptz,boolean)','EXECUTE') then
    raise exception 'Legacy create API bypasses rule selection';
 end if;
 if not has_function_privilege('authenticated',
    'public.athlth_tournament_create_with_rules(text,text,uuid,uuid,integer,integer,uuid[],text[],text,integer,timestamptz,timestamptz,boolean,text[],text,integer,integer)','EXECUTE') then
    raise exception 'Current rule-based create endpoint unavailable';
 end if;
 if not exists(
   select 1 from pg_trigger
   where tgname='athlth_rule_recheck_on_invitation' and tgenabled<>'D'
 ) then
   raise exception 'Pending invitation majority check is missing';
 end if;
 if not exists(
   select 1 from information_schema.columns
   where table_schema='public'
     and table_name='athlth_tournament_match_exercises'
     and column_name='scheduled_at'
 ) then
    raise exception 'Individual exercise opening times missing';
 end if;
end;
$$;
