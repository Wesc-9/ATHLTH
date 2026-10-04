alter table public.user_preferences
  alter column share_training_presence set default false;

update public.user_preferences
set
  share_training_presence = false,
  updated_at = now()
where share_training_presence is distinct from false;
