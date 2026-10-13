-- Regression: direct social challenges must not accept workout evidence
-- before the server has recorded a competitor's acceptance.
begin;
do $$
declare guard_definition text;
begin
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.social_challenge_attempts'::regclass
      and tgname = 'social_challenge_attempt_acceptance_gate'
      and tgenabled = 'O'
  ) then
    raise exception 'Challenge attempts are missing acceptance trigger';
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
    raise exception 'Challenge scoring trigger helper must not be a client RPC';
  end if;

  select pg_get_functiondef(
    'private.guard_social_challenge_attempt_after_acceptance()'::regprocedure
  ) into guard_definition;

  if guard_definition not like '%first_opponent_acceptance%'
     or guard_definition not like '%responded_at%'
     or guard_definition not like '%new.started_at%'
     or guard_definition not like '%new.submitted_at%' then
    raise exception 'Challenge gate must use acceptance and workout timestamps';
  end if;
end;
$$;
rollback;
