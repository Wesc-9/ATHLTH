-- Server-only shared Groq cooldown; no athlete prompts, health details or user identifiers.
create table if not exists public.athlth_ai_provider_cooldowns (
  provider text primary key,
  retry_at timestamptz not null,
  updated_at timestamptz not null default now(),
  constraint valid_provider_key check (provider ~ '^[a-z0-9_-]{1,24}$')
);
alter table public.athlth_ai_provider_cooldowns enable row level security;
revoke all on table public.athlth_ai_provider_cooldowns from public, anon, authenticated;
grant select, insert, update on table public.athlth_ai_provider_cooldowns to service_role;

create or replace function public.athlth_set_ai_provider_cooldown(
  p_provider text, p_seconds integer
) returns void
language sql
security invoker
set search_path = public, pg_temp
as $$
  insert into public.athlth_ai_provider_cooldowns(provider, retry_at, updated_at)
  values (
    p_provider,
    now() + make_interval(secs => greatest(1, least(coalesce(p_seconds,60), 3600))),
    now()
  )
  on conflict (provider)
  do update set
    retry_at = greatest(
      public.athlth_ai_provider_cooldowns.retry_at,
      excluded.retry_at
    ),
    updated_at = now();
$$;

revoke all on function public.athlth_set_ai_provider_cooldown(text, integer)
  from public, anon, authenticated;
grant execute on function public.athlth_set_ai_provider_cooldown(text, integer)
  to service_role;
