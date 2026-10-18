-- Online presence is private to mutual follows (both directions).
-- This is enforced in the RLS helper, not only in the iPhone UI.
-- Preserve: owner self-access, explicit opt-in, block checks, and
-- the existing RLS freshness requirement on social_online_presence.
create or replace function private.can_view_online_status(owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
  select
    (select auth.uid()) = owner_id
    or (
      (select auth.uid()) is not null
      and not private.is_blocked(owner_id)
      and coalesce(
        (
          select s.show_online_status
          from public.profile_social_settings s
          where s.user_id = owner_id
        ),
        false
      )
      and private.is_mutual_follow(owner_id)
    );
$$;

revoke all on function private.can_view_online_status(uuid) from public, anon;
grant execute on function private.can_view_online_status(uuid) to authenticated;
