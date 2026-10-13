-- A challenge invitation is not a scoring window. Require a real,
-- server-timestamped opponent acceptance for every workout result.
-- This protects against stale or older iOS clients uploading retroactively.
create or replace function private.guard_social_challenge_attempt_after_acceptance()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
declare
  challenge_start timestamptz;
  challenge_end timestamptz;
  challenge_status text;
  challenge_creator uuid;
  first_opponent_acceptance timestamptz;
  person_state text;
  person_accepted_at timestamptz;
  performed_at timestamptz;
begin
  select c.starts_at, c.ends_at, c.status, c.creator_id
    into challenge_start, challenge_end, challenge_status, challenge_creator
  from public.social_challenges c
  where c.id = new.challenge_id;

  if not found or challenge_status in ('draft', 'cancelled') then
    raise exception 'Challenge cannot accept workout results';
  end if;

  select min(p.responded_at)
    into first_opponent_acceptance
  from public.social_challenge_participants p
  where p.challenge_id = new.challenge_id
    and p.user_id <> challenge_creator
    and p.state = 'accepted'
    and p.responded_at is not null;

  if first_opponent_acceptance is null then
    raise exception 'Challenge is waiting for opponent acceptance';
  end if;

  select p.state, p.responded_at
    into person_state, person_accepted_at
  from public.social_challenge_participants p
  where p.id = new.participant_id
    and p.challenge_id = new.challenge_id
    and p.user_id = new.user_id;

  if not found or person_state not in ('creator', 'accepted') then
    raise exception 'Participant has not accepted this challenge';
  end if;

  if person_state = 'accepted' and person_accepted_at is null then
    raise exception 'Participant acceptance timestamp is missing';
  end if;

  performed_at := case
    when new.verification = 'manual' then new.submitted_at
    else new.started_at
  end;

  if performed_at is null
     or performed_at < greatest(
          challenge_start,
          first_opponent_acceptance,
          case when person_state = 'accepted'
               then person_accepted_at else challenge_start end
        )
     or (challenge_end is not null and performed_at > challenge_end) then
    raise exception 'Workout started outside the accepted challenge window';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_social_challenge_attempt_after_acceptance()
  from public, anon, authenticated;

drop trigger if exists social_challenge_attempt_acceptance_gate
  on public.social_challenge_attempts;
create trigger social_challenge_attempt_acceptance_gate
before insert on public.social_challenge_attempts
for each row
execute function private.guard_social_challenge_attempt_after_acceptance();

-- Preserve historic entries for audit, but prevent invalid older submissions
-- from affecting scores after upgrades or later invitation acceptance.
update public.social_challenge_attempts a
set is_eligible = false,
    ineligibility_reason = 'Workout started before challenge acceptance'
from public.social_challenges c
join public.social_challenge_participants person
  on person.challenge_id = c.id
left join lateral (
  select min(other.responded_at) as first_accepted_at
  from public.social_challenge_participants other
  where other.challenge_id = c.id
    and other.user_id <> c.creator_id
    and other.state = 'accepted'
    and other.responded_at is not null
) acceptance on true
where a.challenge_id = c.id
  and a.participant_id = person.id
  and a.is_eligible
  and (
    c.status in ('draft', 'cancelled')
    or person.state not in ('creator', 'accepted')
    or (person.state = 'accepted' and person.responded_at is null)
    or acceptance.first_accepted_at is null
    or (case when a.verification = 'manual'
             then a.submitted_at else a.started_at end) is null
    or (case when a.verification = 'manual'
             then a.submitted_at else a.started_at end) <
       greatest(
         c.starts_at,
         acceptance.first_accepted_at,
         case when person.state = 'accepted'
              then person.responded_at else c.starts_at end
       )
    or (
      c.ends_at is not null and
      (case when a.verification = 'manual'
            then a.submitted_at else a.started_at end) > c.ends_at
    )
  );
