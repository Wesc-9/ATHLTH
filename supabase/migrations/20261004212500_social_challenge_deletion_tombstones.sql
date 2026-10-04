-- Prevent an already-deleted social challenge from being resurrected by
-- a stale local copy on another signed-in device.

create table if not exists private.social_challenge_deletions (
  challenge_id uuid primary key,
  creator_id uuid not null,
  deleted_at timestamptz not null default now()
);

create or replace function private.guard_deleted_social_challenge_insert()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  if exists (
    select 1
    from private.social_challenge_deletions d
    where d.challenge_id = new.id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'Challenge has been deleted';
  end if;

  return new;
end;
$$;

drop trigger if exists social_challenges_guard_deleted_insert
on public.social_challenges;

create trigger social_challenges_guard_deleted_insert
before insert on public.social_challenges
for each row execute function private.guard_deleted_social_challenge_insert();

create or replace function public.delete_social_challenge(
  p_challenge_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_creator uuid;
begin
  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  select creator_id
    into v_creator
  from public.social_challenges
  where id = p_challenge_id
  for update;

  if v_creator is null then
    -- Preserve idempotency. If this device is repeating a successful delete,
    -- there is nothing left to remove.
    return;
  end if;

  if v_creator <> v_actor then
    raise exception 'Only the challenge creator can delete this challenge';
  end if;

  insert into private.social_challenge_deletions(
    challenge_id,
    creator_id,
    deleted_at
  )
  values (
    p_challenge_id,
    v_actor,
    now()
  )
  on conflict (challenge_id)
  do update set
    creator_id = excluded.creator_id,
    deleted_at = excluded.deleted_at;

  delete from public.social_inbox_events
  where entity_type = 'challenge'
    and entity_id = p_challenge_id;

  delete from public.social_activities
  where event_key = 'challenge-' || p_challenge_id::text || '-created';

  delete from public.social_challenges
  where id = p_challenge_id
    and creator_id = v_actor;
end;
$$;

revoke all on function public.delete_social_challenge(uuid)
from public, anon;

grant execute on function public.delete_social_challenge(uuid)
to authenticated;
