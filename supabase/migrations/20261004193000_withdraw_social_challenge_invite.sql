-- Allow a challenge creator to withdraw one unanswered invite without
-- cancelling the entire challenge or affecting other participants.

create or replace function public.withdraw_social_challenge_invite(
  p_participant_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_challenge_id uuid;
  v_recipient_id uuid;
  v_state text;
  v_creator_id uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;

  select
    p.challenge_id,
    p.user_id,
    p.state,
    c.creator_id
  into
    v_challenge_id,
    v_recipient_id,
    v_state,
    v_creator_id
  from public.social_challenge_participants p
  join public.social_challenges c
    on c.id = p.challenge_id
  where p.id = p_participant_id;

  if v_challenge_id is null then
    return;
  end if;

  if v_creator_id <> v_actor then
    raise exception 'Only the challenge creator can withdraw an invite';
  end if;

  if v_state <> 'invited' then
    raise exception 'Only unanswered challenge invites can be withdrawn';
  end if;

  delete from public.social_inbox_events
  where recipient_id = v_recipient_id
    and kind = 'challenge_invite'
    and entity_type = 'challenge'
    and entity_id = v_challenge_id;

  delete from public.social_challenge_participants
  where id = p_participant_id;
end;
$$;

revoke all on function public.withdraw_social_challenge_invite(uuid)
from public, anon;

grant execute on function public.withdraw_social_challenge_invite(uuid)
to authenticated;
