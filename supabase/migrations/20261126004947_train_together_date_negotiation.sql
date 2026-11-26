-- Date negotiations are independent of exercise-edit permissions.
alter table public.social_workout_draft_lobbies
  add column if not exists proposed_start double precision,
  add column if not exists proposed_start_by uuid;

alter table public.social_workout_draft_lobbies
  add constraint social_workout_pending_start_requires_review check (
    (proposed_start is null and proposed_start_by is null) or
    (proposed_start is not null and proposed_start_by is not null
     and proposed_start_by in (owner_id, partner_id)
     and owner_approved_revision is null and partner_approved_revision is null)
  );

create or replace function public.negotiate_social_workout_start(
  p_source_id uuid, p_expected_revision integer,
  p_accept boolean, p_start double precision default null
) returns public.social_workout_draft_lobbies
language plpgsql security definer set search_path = pg_catalog, public, private
as $$
declare
  v_actor uuid := (select auth.uid());
  v_row public.social_workout_draft_lobbies;
  v_now double precision := extract(epoch from (now() - timestamptz '2001-01-01 00:00:00+00'));
begin
  select * into v_row from public.social_workout_draft_lobbies
    where source_workout_id = p_source_id for update;
  if not found or v_actor is null or v_actor not in (v_row.owner_id, v_row.partner_id)
    or v_row.cancelled_at is not null then
    raise exception 'Workout draft unavailable';
  end if;
  if not private.are_friends(case when v_actor = v_row.owner_id then v_row.partner_id else v_row.owner_id end)
     or private.is_blocked(case when v_actor = v_row.owner_id then v_row.partner_id else v_row.owner_id end) then
    raise exception 'Workout partner unavailable';
  end if;
  if v_row.revision <> p_expected_revision then
    raise exception 'Workout changed. Refresh before responding';
  end if;
  if exists (select 1 from public.social_workout_sessions s
      where s.source_workout_id = p_source_id and s.creator_id = v_row.owner_id
        and s.status not in ('cancelled','completed')) then
    raise exception 'The Ready lobby has already been opened';
  end if;
  if p_accept then
    if v_row.proposed_start is null or v_row.proposed_start_by = v_actor
        or v_row.proposed_start <= v_now then
      raise exception 'No current date proposal from the other athlete';
    end if;
    update public.social_workout_draft_lobbies set
      workout_snapshot = jsonb_set(workout_snapshot::jsonb, '{scheduledStart}',
          to_jsonb(proposed_start), true)::text,
      proposed_start = null, proposed_start_by = null,
      revision = revision + 1, owner_approved_revision = null,
      partner_approved_revision = null, updated_at = now()
      where source_workout_id = p_source_id returning * into v_row;
  else
    if p_start is null or not (p_start > v_now and p_start < v_now + 315576000) then
      raise exception 'Choose a future workout date';
    end if;
    update public.social_workout_draft_lobbies set
      proposed_start = p_start, proposed_start_by = v_actor,
      revision = revision + 1, owner_approved_revision = null,
      partner_approved_revision = null, updated_at = now()
      where source_workout_id = p_source_id returning * into v_row;
  end if;
  return v_row;
end;
$$;
revoke all on function public.negotiate_social_workout_start(uuid,integer,boolean,double precision) from public, anon;
grant execute on function public.negotiate_social_workout_start(uuid,integer,boolean,double precision) to authenticated;
