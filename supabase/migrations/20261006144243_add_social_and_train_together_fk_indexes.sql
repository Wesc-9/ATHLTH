-- Cover foreign keys used by inbox, live social workouts and Train Together.
-- These indexes keep deletes/joins predictable as the social tables grow.

create index if not exists social_inbox_events_actor_idx
  on public.social_inbox_events (actor_id);

create index if not exists social_workout_live_states_user_idx
  on public.social_workout_live_states (user_id);

create index if not exists social_workout_messages_sender_idx
  on public.social_workout_messages (sender_id);

create index if not exists train_together_post_meetups_creator_idx
  on public.train_together_post_meetups (creator_id);

create index if not exists train_together_posts_social_workout_session_idx
  on public.train_together_posts (social_workout_session_id);
