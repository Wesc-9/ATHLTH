create or replace function private.lock_started_group_challenge_rules()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if old.starts_at <= now()
     and (
       old.starts_at is distinct from new.starts_at
       or old.ends_at is distinct from new.ends_at
       or old.metric is distinct from new.metric
       or old.target_value is distinct from new.target_value
       or old.activity_config is distinct from new.activity_config
       or old.scoring_mode is distinct from new.scoring_mode
       or old.attempt_limit is distinct from new.attempt_limit
       or old.route_verification_enabled is distinct from new.route_verification_enabled
       or old.route_tolerance_meters is distinct from new.route_tolerance_meters
       or old.join_required is distinct from new.join_required
     )
  then
    raise exception 'Challenge competition rules are locked after the challenge starts';
  end if;

  return new;
end;
$$;

revoke all on function private.lock_started_group_challenge_rules()
from public, anon, authenticated;
