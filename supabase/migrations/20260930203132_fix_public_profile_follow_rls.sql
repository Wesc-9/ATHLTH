create or replace function private.can_follow_public_profile(target_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select s.profile_visibility = 'public'
      from public.profile_social_settings s
      where s.user_id = target_user
      limit 1
    ),
    (
      select c.profile_visibility = 'public'
      from public.social_profile_cards c
      where c.user_id = target_user
      limit 1
    ),
    false
  );
$$;

revoke all on function private.can_follow_public_profile(uuid)
from public, anon, authenticated;

grant execute on function private.can_follow_public_profile(uuid)
to authenticated;

drop policy if exists "users can follow public profiles from their own account"
on public.profile_follows;

create policy "users can follow public profiles from their own account"
on public.profile_follows
for insert
to authenticated
with check (
  (select auth.uid()) = follower_id
  and follower_id <> following_id
  and private.can_follow_public_profile(following_id)
);
