-- Phase 4: a delayed remote-start callback must never rewrite a terminal
-- result or change the identity/claim owner of a queued HealthKit launch.
-- Existing rows and their history are preserved; no destructive migration.
create or replace function public.protect_workout_device_command_transition()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.user_id is distinct from new.user_id
     or old.client_request_id is distinct from new.client_request_id
     or old.source_device is distinct from new.source_device
     or old.target_device is distinct from new.target_device
     or old.command_kind is distinct from new.command_kind
     or old.payload is distinct from new.payload
     or old.created_at is distinct from new.created_at
     or old.expires_at is distinct from new.expires_at then
    raise exception 'Workout relay identity is immutable';
  end if;

  if old.claimed_at is not null and (
       old.claimed_at is distinct from new.claimed_at
       or old.claimed_by_device_id is distinct from new.claimed_by_device_id
  ) then
    raise exception 'Workout relay claim owner is immutable';
  end if;

  if old.completed_at is not null or old.failed_at is not null then
    if new is distinct from old then
      raise exception 'Terminal workout relay commands are immutable';
    end if;
    return new;
  end if;

  if new.completed_at is not null and new.failed_at is not null then
    raise exception 'Workout relay cannot be both completed and failed';
  end if;
  if (new.completed_at is not null or new.failed_at is not null)
     and (new.claimed_at is null or new.claimed_by_device_id is null) then
    raise exception 'Workout relay must be claimed before acknowledgement';
  end if;
  return new;
end;
$function$;

drop trigger if exists protect_workout_device_command_transition
  on public.workout_device_commands;
create trigger protect_workout_device_command_transition
before update on public.workout_device_commands
for each row execute function public.protect_workout_device_command_transition();

revoke all on function public.protect_workout_device_command_transition()
  from public, anon, authenticated;
