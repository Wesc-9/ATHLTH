-- The outer RLS policy runs with the viewer's privileges. Reading
-- another account's profile_social_settings directly from that policy
-- can be filtered by that table's own RLS. Do the consent test in a
-- narrowly scoped SECURITY DEFINER helper, exactly like online presence.
create or replace function private.can_view_training_now(owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    (select auth.uid()) is not null
    and (select auth.uid()) <> owner_id
    and not private.is_blocked(owner_id)
    and private.is_mutual_follow(owner_id)
    and coalesce(
      (
        select s.share_training_presence
        from public.profile_social_settings s
        where s.user_id = owner_id
      ),
      false
    );
$$;

revoke all on function private.can_view_training_now(uuid)
from public, anon;
grant execute on function private.can_view_training_now(uuid)
to authenticated;

drop policy if exists social_presence_select_allowed on public.social_presence;
create policy social_presence_select_allowed
  on public.social_presence
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      state = 'training'
      and updated_at > now() - interval '3 minutes'
      and private.can_view_training_now(user_id)
    )
  );
