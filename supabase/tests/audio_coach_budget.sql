-- Replay against disposable Supabase in CI only. All fixtures roll back.
begin;

do $$
declare
  athlete uuid := 'c0a00000-0000-4000-8000-000000000001';
  outcome record;
  n integer;
begin
  insert into auth.users(id) values (athlete);

  for n in 1..3 loop
    -- The common per-minute bucket must be refreshed between normal starts.
    -- We deliberately preserve the daily bucket in this transaction.
    update private.ai_request_budgets
    set minute_start = clock_timestamp() - interval '2 minutes',
        minute_units = 0
    where user_id = athlete;

    select * into outcome
    from public.consume_ai_request_budget(athlete, 'audio-coach-realtime');
    if outcome.allowed is distinct from true then
      raise exception 'Expected voice reservation % to be admitted', n;
    end if;
  end loop;

  update private.ai_request_budgets
  set minute_start = clock_timestamp() - interval '2 minutes',
      minute_units = 0
  where user_id = athlete;

  select * into outcome
  from public.consume_ai_request_budget(athlete, 'audio-coach-realtime');
  if outcome.allowed is distinct from false or outcome.retry_after <= 0 then
    raise exception 'Voice daily limit failed to refuse fourth start';
  end if;

  -- Other AI features keep their existing independent cost and access.
  select * into outcome
  from public.consume_ai_request_budget(athlete, 'workout-insight');
  if outcome.allowed is distinct from true then
    raise exception 'Voice budget changes broke ordinary workout insight';
  end if;

  if has_function_privilege(
    'anon', 'public.consume_ai_request_budget(uuid,text)', 'EXECUTE'
  ) then
    raise exception 'Anon gained access to service-only budget function';
  end if;
end $$;

rollback;
