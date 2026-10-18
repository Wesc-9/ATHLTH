-- Private workout-presence signal, no other viewer than a mutual follower.
-- Sharing must be explicitly enabled, and a stopped heartbeat expires.
drop policy if exists social_presence_select_allowed on public.social_presence;
create policy social_presence_select_allowed
  on public.social_presence
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      state = 'training'
      and updated_at > now() - interval '3 minutes'
      and not private.is_blocked(user_id)
      and private.is_mutual_follow(user_id)
      and coalesce((
        select s.share_training_presence
        from public.profile_social_settings s
        where s.user_id = social_presence.user_id
      ), false)
    )
  );
