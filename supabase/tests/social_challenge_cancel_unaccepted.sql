-- Challenge status and invitation acceptance are server-authoritative.
-- New clients may be bypassed; these guards must still refuse false outcomes.
begin;
select 1 / case when exists (
    select 1 from pg_trigger
    where tgname = 'social_challenge_activation_guard' and not tgisinternal
  ) then 1 else 0 end;
select 1 / case when exists (
    select 1 from pg_trigger
    where tgname = 'social_challenge_acceptance_deadline_guard' and not tgisinternal
  ) then 1 else 0 end;
select 1 / case when exists (
    select 1 from pg_proc
    where proname = 'expire_unaccepted_social_challenges'
  ) then 1 else 0 end;
rollback;
