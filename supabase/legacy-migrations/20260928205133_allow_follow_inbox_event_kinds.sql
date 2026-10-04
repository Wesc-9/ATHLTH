-- Preserve legacy inbox event kinds while allowing the follow-only product
-- terminology used by new profile follow requests.
alter table public.social_inbox_events
  drop constraint if exists social_inbox_events_kind_check;

alter table public.social_inbox_events
  add constraint social_inbox_events_kind_check
  check (
    kind = any (
      array[
        'friend_request'::text,
        'friend_accepted'::text,
        'follow_request'::text,
        'follow_accepted'::text,
        'challenge_invite'::text,
        'challenge_result'::text,
        'reaction'::text,
        'workout_invite'::text,
        'workout_invite_accepted'::text,
        'message'::text,
        'message_request'::text,
        'message_request_accepted'::text,
        'mention'::text,
        'group_message'::text,
        'group_update'::text,
        'group_event'::text,
        'group_challenge'::text,
        'group_invite'::text,
        'group_join_request'::text,
        'group_join_approved'::text
      ]
    )
  );
