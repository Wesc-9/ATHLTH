alter table public.social_workout_sessions
  add column if not exists invite_payload jsonb;

comment on column public.social_workout_sessions.invite_payload is
  'Versioned ATHLTH workout snapshot used to launch an accepted Train Together invitation.';

alter table public.social_workout_sessions
  drop constraint if exists social_workout_sessions_invite_payload_size_check;

alter table public.social_workout_sessions
  add constraint social_workout_sessions_invite_payload_size_check
  check (
    invite_payload is null
    or octet_length(invite_payload::text) <= 1048576
  );
