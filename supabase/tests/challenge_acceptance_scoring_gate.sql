-- Non-mutating acceptance gate regression checks for disposable Supabase.
begin;
do $$
declare
  gate_oid oid;
  trigger_function text;
begin
  select t.tgfoid
    into gate_oid
  from pg_trigger t
  where t.tgrelid = 'public.social_challenge_attempts'::regclass
    and t.tgname = 'social_challenge_attempt_acceptance_gate'
    and t.tgenabled = 'O'
    and (t.tgtype & 2) = 2 -- BEFORE
    and (t.tgtype & 4) = 4; -- INSERT
  if gate_oid is null then
    raise exception 'Challenge result insert has no live acceptance gate';
  end if;

  select pg_get_functiondef(gate_oid) into trigger_function;
  if trigger_function not like '%first_opponent_acceptance%'
     or trigger_function not like '%person_accepted_at%'
     or trigger_function not like '%new.started_at%'
     or trigger_function not like '%new.submitted_at%' then
    raise exception 'Challenge result acceptance gate is missing critical time checks';
  end if;

  if has_function_privilege(
       'anon',
       'private.guard_social_challenge_attempt_after_acceptance()'::regprocedure,
       'EXECUTE'
     ) or has_function_privilege(
       'authenticated',
       'private.guard_social_challenge_attempt_after_acceptance()'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Acceptance guard must not be callable as a client RPC';
  end if;

  if not (select relrowsecurity
          from pg_class
          where oid = 'public.social_challenge_attempts'::regclass) then
    raise exception 'Challenge results require row-level security';
  end if;
end;
$$;
rollback;
