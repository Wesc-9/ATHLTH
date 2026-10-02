-- Preserve a launchable snapshot for "Train Together" invitations.
-- The recipient receives an immutable copy of the workout configuration that
-- existed when the creator sent the invitation. Device choice remains local.
alter table public.social_workout_sessions
  add column if not exists invite_payload jsonb;

comment on column public.social_workout_sessions.invite_payload is
  'Versioned ATHLTH workout snapshot used to launch an accepted Train Together invitation.';

-- Keep payload size bounded. A route with normal workout coordinates and a
-- structured workout fits comfortably below this limit, while accidental
-- oversized writes are rejected.
alter table public.social_workout_sessions
  drop constraint if exists social_workout_sessions_invite_payload_size_check;

alter table public.social_workout_sessions
  add constraint social_workout_sessions_invite_payload_size_check
  check (
    invite_payload is null
    or octet_length(invite_payload::text) <= 1048576
  );
