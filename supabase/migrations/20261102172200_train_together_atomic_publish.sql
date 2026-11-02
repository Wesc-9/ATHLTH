-- One transaction for Train Together publication and its private meetup.
-- SECURITY INVOKER preserves the existing insert/select RLS policies.
-- No direct access to private meetup details is granted to the public.
create or replace function public.publish_train_together_post(
    p_post jsonb,
    p_meetup jsonb default null
)
returns uuid
language plpgsql
security invoker
set search_path to pg_catalog, public
as $function$
declare
    v_actor uuid := (select auth.uid());
    v_post_id uuid;
begin
    if v_actor is null then
        raise exception 'Authentication required';
    end if;
    if p_post is null or jsonb_typeof(p_post) <> 'object' then
        raise exception 'Invalid Train Together workout';
    end if;
    if nullif(p_post ->> 'creator_id', '')::uuid is distinct from v_actor then
        raise exception 'Cannot publish another athlete''s workout';
    end if;

    insert into public.train_together_posts (
        id, creator_id, creator_display_name, creator_username,
        creator_avatar_url, title, workout_kind, scheduled_start,
        duration_minutes, distance_kilometers, level, broad_area,
        note, max_guests, accepted_guests, status,
        participation_mode, join_policy, workout_payload,
        source_planned_session_id
    ) values (
        (p_post ->> 'id')::uuid,
        v_actor,
        p_post ->> 'creator_display_name',
        p_post ->> 'creator_username',
        p_post ->> 'creator_avatar_url',
        p_post ->> 'title',
        p_post ->> 'workout_kind',
        (p_post ->> 'scheduled_start')::timestamptz,
        (p_post ->> 'duration_minutes')::integer,
        (p_post ->> 'distance_kilometers')::double precision,
        coalesce(p_post ->> 'level', 'all'),
        p_post ->> 'broad_area',
        p_post ->> 'note',
        (p_post ->> 'max_guests')::integer,
        0,
        'open',
        coalesce(p_post ->> 'participation_mode', 'physical'),
        coalesce(p_post ->> 'join_policy', 'request'),
        nullif(p_post -> 'workout_payload', 'null'::jsonb),
        nullif(p_post ->> 'source_planned_session_id', '')::uuid
    ) returning id into v_post_id;

    if p_meetup is not null then
        if jsonb_typeof(p_meetup) <> 'object' then
            raise exception 'Invalid Train Together meetup';
        end if;
        if nullif(p_meetup ->> 'creator_id', '')::uuid is distinct from v_actor
           or nullif(p_meetup ->> 'post_id', '')::uuid is distinct from v_post_id then
            raise exception 'Meetup must belong to the published workout';
        end if;
        insert into public.train_together_post_meetups (
            post_id, creator_id, meeting_name, meeting_address,
            meeting_latitude, meeting_longitude, meeting_details
        ) values (
            v_post_id,
            v_actor,
            p_meetup ->> 'meeting_name',
            p_meetup ->> 'meeting_address',
            (p_meetup ->> 'meeting_latitude')::double precision,
            (p_meetup ->> 'meeting_longitude')::double precision,
            p_meetup ->> 'meeting_details'
        );
    end if;
    return v_post_id;
end;
$function$;

revoke all on function public.publish_train_together_post(jsonb, jsonb)
from public, anon;
grant execute on function public.publish_train_together_post(jsonb, jsonb)
to authenticated;
