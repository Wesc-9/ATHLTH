-- New users explicitly choose whether to share Health-derived information.
-- Existing settings are preserved; no consent can be inferred from old defaults.
alter table public.profile_social_settings
  alter column training_focus_visibility set default 'private',
  alter column performance_stats_visibility set default 'private',
  alter column trophy_cabinet_visibility set default 'private',
  alter column recent_activity_visibility set default 'private',
  alter column goals_visibility set default 'private',
  alter column gear_visibility set default 'private',
  alter column running_prs_visibility set default 'private',
  alter column strength_prs_visibility set default 'private',
  alter column share_performance_stats set default false,
  alter column share_trophy_cabinet set default false,
  alter column share_goals set default false,
  alter column share_gear set default false,
  alter column share_recent_activity set default false,
  alter column share_running_prs set default false,
  alter column share_strength_prs set default false,
  alter column share_workout_totals set default false;

-- Stable image_url locators are resolved to short-lived signed URLs by 1.6.0.
update storage.buckets set public = false where id = 'workout-media';
drop policy if exists "workout media storage select owner" on storage.objects;
create policy "workout media storage authorized read"
on storage.objects for select to authenticated
using (
  bucket_id = 'workout-media' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.workout_media m where m.storage_path = name
    )
    or exists (
      select 1 from public.community_events e
      where name = e.creator_id::text || '/event-covers/' || e.id::text || '.jpg'
    )
    or exists (
      select 1 from public.social_challenges c
      where name = c.creator_id::text || '/challenge-covers/' || c.id::text || '.jpg'
    )
  )
);
-- The subqueries above run as the caller, so metadata RLS determines audience.

-- Inventory only. Delete bytes through the Storage API, never SQL DELETE.
-- Include legacy paths and objects uploaded into shared group directories.
create or replace function public.account_storage_objects_for_deletion(
  p_user_id uuid, p_limit integer default 100
)
returns table(bucket_id text, name text)
language sql stable security definer
set search_path = ''
as $function$
  select o.bucket_id, o.name
  from storage.objects o
  where o.owner_id = p_user_id::text
     or o.owner = p_user_id
     or (
       o.bucket_id in ('profile-avatars', 'profile-gear', 'workout-media')
       and (storage.foldername(o.name))[1] = p_user_id::text
     )
  order by o.bucket_id, o.name
  limit least(greatest(coalesce(p_limit, 100), 1), 100);
$function$;

-- Shared cost budget across Recovery, Workout, Program and Adaptation.
-- One unit for an insight, five for program generation/adaptation.
create table private.ai_request_budgets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  minute_start timestamptz not null,
  day_start timestamptz not null,
  minute_units integer not null default 0,
  day_units integer not null default 0
);
alter table private.ai_request_budgets enable row level security;
revoke all on private.ai_request_budgets from public, anon, authenticated;

create function public.consume_ai_request_budget(p_user_id uuid, p_feature text)
returns table(allowed boolean, retry_after integer)
language plpgsql security definer set search_path = ''
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
    when 'generate-training-program', 'generate-plan-adaptation' then cost := 5;
    else raise exception 'Unknown AI feature';
  end case;
  insert into private.ai_request_budgets(user_id, minute_start, day_start)
  values (p_user_id, minute_stamp, day_stamp) on conflict do nothing;
  select * into budget from private.ai_request_budgets
  where user_id = p_user_id for update;
  -- Time may have advanced while waiting for another request's row lock.
  stamp := clock_timestamp();
  minute_stamp := date_trunc('minute', stamp);
  day_stamp := date_trunc('day', stamp, 'UTC');
  if budget.minute_start <> minute_stamp then budget.minute_units := 0; end if;
  if budget.day_start <> day_stamp then budget.day_units := 0; end if;
  if budget.minute_units + cost > 10 then
    retry := greatest(1, ceil(extract(epoch from minute_stamp + interval '1 minute' - stamp))::integer);
  end if;
  if budget.day_units + cost > 100 then
    retry := greatest(retry, ceil(extract(epoch from day_stamp + interval '1 day' - stamp))::integer);
  end if;
  update private.ai_request_budgets set
    minute_start = minute_stamp, day_start = day_stamp,
    minute_units = budget.minute_units + case when retry = 0 then cost else 0 end,
    day_units = budget.day_units + case when retry = 0 then cost else 0 end
  where user_id = p_user_id;
  return query select retry = 0, retry;
end;
$function$;
revoke all on function public.consume_ai_request_budget(uuid, text) from public, anon, authenticated;
grant execute on function public.consume_ai_request_budget(uuid, text) to service_role;
revoke all on function public.account_storage_objects_for_deletion(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.account_storage_objects_for_deletion(uuid, integer)
  to service_role;

-- Align availability with the profiles constraint and the app validator.
create or replace function private.is_username_available_impl(candidate text)
returns boolean
language plpgsql stable security definer
set search_path = pg_catalog
as $function$
declare
  actor uuid := auth.uid();
  cleaned text := lower(trim(candidate));
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if cleaned is null or cleaned !~ '^[a-z0-9_]{3,20}$' then return false; end if;
  return not exists (
    select 1 from public.profiles p
    where lower(p.username) = cleaned and p.id <> actor
  );
end;
$function$;
