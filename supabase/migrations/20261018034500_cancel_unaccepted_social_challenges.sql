-- A challenge invitation must never become a contest before at least
-- one opponent explicitly accepts. Protect against old clients marking
-- unaccepted invitations "upcoming", "active" or "completed".
-- This migration is applied server-side; committing it does not deploy it.

create or replace function private.guard_social_challenge_activation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
begin
  if new.status in ('upcoming', 'active', 'completed')
     and not exists (
       select 1
       from public.social_challenge_participants p
       where p.challenge_id = new.id
         and p.user_id <> new.creator_id
         and p.state = 'accepted'
         and p.responded_at is not null
     ) then
    raise exception 'A challenge must be accepted by an opponent before it can start or finish';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_social_challenge_activation()
  from public, anon, authenticated;

drop trigger if exists social_challenge_activation_guard
  on public.social_challenges;

create trigger social_challenge_activation_guard
before insert or update of status on public.social_challenges
for each row execute function private.guard_social_challenge_activation();

-- Acceptance after the contest's end must not retroactively create a
-- winner or unlock historical workouts. Preserve other participant
-- transitions (decline and invitation withdrawal) as they are.
create or replace function private.guard_social_challenge_acceptance_deadline()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
declare
  deadline timestamptz;
  challenge_status text;
begin
  if tg_op <> 'UPDATE'
     or old.state <> 'invited'
     or new.state <> 'accepted' then
    return new;
  end if;

  select c.ends_at, c.status
    into deadline, challenge_status
  from public.social_challenges c
  where c.id = new.challenge_id;

  if challenge_status in ('draft', 'cancelled', 'completed')
     or (deadline is not null and clock_timestamp() >= deadline) then
    raise exception 'The challenge invitation has expired';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_social_challenge_acceptance_deadline()
  from public, anon, authenticated;

drop trigger if exists social_challenge_acceptance_deadline_guard
  on public.social_challenge_participants;

create trigger social_challenge_acceptance_deadline_guard
before update of state on public.social_challenge_participants
for each row execute function private.guard_social_challenge_acceptance_deadline();

-- Correct existing erroneous outcomes, without altering competitions in
-- which an opponent did accept. Never award a solo result.
update public.social_challenges c
set status = 'cancelled',
    updated_at = now()
where c.status in ('invited', 'upcoming', 'active', 'completed')
  and c.ends_at is not null
  and c.ends_at <= now()
  and not exists (
    select 1
    from public.social_challenge_participants p
    where p.challenge_id = c.id
      and p.user_id <> c.creator_id
      and p.state = 'accepted'
      and p.responded_at is not null
  );

-- Remove legacy fabricated result-inbox events generated for contests
-- that never acquired a valid opponent. Invitations are preserved so a
-- recipient still receives the initial invitation at creation time.
delete from public.social_inbox_events event
using public.social_challenges c
where event.entity_type = 'challenge'
  and event.entity_id = c.id
  and event.kind = 'challenge_result'
  and c.status = 'cancelled'
  and c.ends_at is not null
  and c.ends_at <= now()
  and not exists (
    select 1 from public.social_challenge_participants p
    where p.challenge_id = c.id
      and p.user_id <> c.creator_id
      and p.state = 'accepted'
      and p.responded_at is not null
  );

-- Lazy server reconciliation whenever an authorized athlete reloads
-- challenges. A user can only expire their own or joined challenge rows.
create or replace function public.expire_unaccepted_social_challenges()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  count_cancelled integer := 0;
begin
  if actor is null then
    raise exception 'Authentication required';
  end if;

  with expired as (
    update public.social_challenges c
    set status = 'cancelled',
        updated_at = now()
    where c.status in ('invited', 'upcoming', 'active', 'completed')
      and c.ends_at is not null
      and c.ends_at <= now()
      and (
        c.creator_id = actor
        or exists (
          select 1 from public.social_challenge_participants m
          where m.challenge_id = c.id and m.user_id = actor
        )
      )
      and not exists (
        select 1 from public.social_challenge_participants p
        where p.challenge_id = c.id
          and p.user_id <> c.creator_id
          and p.state = 'accepted'
          and p.responded_at is not null
      )
    returning c.id
  )
  select count(*) into count_cancelled from expired;

  delete from public.social_inbox_events event
  using public.social_challenges c
  where event.entity_type = 'challenge'
    and event.entity_id = c.id
    and event.kind = 'challenge_result'
    and c.status = 'cancelled'
    and c.ends_at is not null
    and c.ends_at <= now()
    and (
      c.creator_id = actor
      or event.recipient_id = actor
    )
    and not exists (
      select 1 from public.social_challenge_participants p
      where p.challenge_id = c.id
        and p.user_id <> c.creator_id
        and p.state = 'accepted'
        and p.responded_at is not null
    );

  return count_cancelled;
end;
$$;

revoke all on function public.expire_unaccepted_social_challenges()
  from public, anon;

grant execute on function public.expire_unaccepted_social_challenges()
  to authenticated;
