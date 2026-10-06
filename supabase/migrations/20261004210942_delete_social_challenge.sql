-- Delete a personal ATHLTH challenge completely when the creator confirms deletion.
-- Related participants, attempts and check-ins cascade through challenge_id foreign keys.
-- Inbox/feed rows use loose entity references, so clean those explicitly.

create or replace function public.delete_social_challenge(
  p_challenge_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_creator uuid;
begin
  if v_actor is null then
    raise exception 'Not authenticated';
  end if;

  select creator_id
    into v_creator
  from public.social_challenges
  where id = p_challenge_id
  for update;

  if v_creator is null then
    -- Idempotent delete: if another device already removed it, treat as done.
    return;
  end if;

  if v_creator <> v_actor then
    raise exception 'Only the challenge creator can delete this challenge';
  end if;

  delete from public.social_inbox_events
  where entity_type = 'challenge'
    and entity_id = p_challenge_id;

  delete from public.social_activities
  where event_key = 'challenge-' || p_challenge_id::text || '-created';

  delete from public.social_challenges
  where id = p_challenge_id
    and creator_id = v_actor;
end;
$$;

revoke all on function public.delete_social_challenge(uuid)
from public, anon;

grant execute on function public.delete_social_challenge(uuid)
to authenticated;
