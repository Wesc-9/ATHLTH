-- ATHLTH 1.7.3: strength-exercise-planner invokes the existing metered AI
-- budget RPC. Teach the RPC this feature without changing limits,
-- privileges, reset behavior, existing feature costs, or stored counters.
create or replace function public.consume_ai_request_budget(
  p_user_id uuid,
  p_feature text
) returns table(allowed boolean, retry_after integer)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  stamp timestamptz := clock_timestamp();
  minute_stamp timestamptz := date_trunc('minute', stamp);
  day_stamp timestamptz := date_trunc('day', stamp, 'UTC');
  cost integer;
  budget private.ai_request_budgets%rowtype;
  retry integer := 0;
begin
  case p_feature
    when 'recovery-sense', 'workout-insight' then cost := 1;
    when 'generate-training-program', 'generate-plan-adaptation',
         'strength-exercise-planner' then cost := 5;
    else raise exception 'Unknown AI feature';
  end case;

  insert into private.ai_request_budgets(user_id, minute_start, day_start)
  values (p_user_id, minute_stamp, day_stamp) on conflict do nothing;

  select * into budget from private.ai_request_budgets
  where user_id = p_user_id for update;

  -- Recompute times after acquiring the row lock.
  stamp := clock_timestamp();
  minute_stamp := date_trunc('minute', stamp);
  day_stamp := date_trunc('day', stamp, 'UTC');
  if budget.minute_start <> minute_stamp then budget.minute_units := 0; end if;
  if budget.day_start <> day_stamp then budget.day_units := 0; end if;
  if budget.minute_units + cost > 10 then
    retry := greatest(
      1,
      ceil(extract(epoch from minute_stamp + interval '1 minute' - stamp))::integer
    );
  end if;
  if budget.day_units + cost > 100 then
    retry := greatest(
      retry,
      ceil(extract(epoch from day_stamp + interval '1 day' - stamp))::integer
    );
  end if;
  update private.ai_request_budgets set
    minute_start = minute_stamp,
    day_start = day_stamp,
    minute_units = budget.minute_units + case when retry = 0 then cost else 0 end,
    day_units = budget.day_units + case when retry = 0 then cost else 0 end
  where user_id = p_user_id;

  return query select retry = 0, retry;
end;
$function$;
