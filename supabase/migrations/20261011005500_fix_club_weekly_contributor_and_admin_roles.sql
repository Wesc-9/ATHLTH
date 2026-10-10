-- ATHLTH 1.7.1: ensure Contributor can publish curated weekly goals
-- without enabling ordinary event/route-challenge creation in restricted Clubs.
-- No tables/data are removed; existing weekly challenges remain intact.

CREATE OR REPLACE FUNCTION public.create_community_group_weekly_challenge_v1(
  p_id uuid,
  p_group_id uuid,
  p_title text,
  p_summary text,
  p_metric text,
  p_target_value double precision,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_image_url text,
  p_activity_config jsonb,
  p_options jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
BEGIN
  IF v_actor IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.community_groups g
    LEFT JOIN public.community_group_members m
      ON m.group_id = g.id AND m.user_id = v_actor
    WHERE g.id = p_group_id
      AND (g.creator_id = v_actor
           OR m.role IN ('owner', 'admin', 'contributor'))
  ) THEN
    RAISE EXCEPTION 'Only owners, admins and contributors can create weekly Club challenges';
  END IF;

  IF char_length(trim(coalesce(p_title, ''))) NOT BETWEEN 1 AND 160
     OR char_length(coalesce(p_summary, '')) > 800 THEN
    RAISE EXCEPTION 'Invalid weekly challenge title or description';
  END IF;

  IF p_metric NOT IN ('workouts', 'distance_km', 'active_minutes') THEN
    RAISE EXCEPTION 'Weekly Club challenges support workouts, distance or training minutes';
  END IF;

  IF p_target_value IS NULL
     OR NOT isfinite(p_target_value)
     OR p_target_value <= 0 THEN
    RAISE EXCEPTION 'Weekly goal must be a finite positive value';
  END IF;

  IF p_starts_at IS NULL OR p_ends_at IS NULL
     OR p_ends_at <= p_starts_at THEN
    RAISE EXCEPTION 'Weekly challenge must end after it starts';
  END IF;

  IF p_activity_config IS NOT NULL THEN
    RAISE EXCEPTION 'Route and activity-specific challenges belong in New challenge';
  END IF;

  -- The dedicated weekly RPC defines the limited rules. It does not use
  -- private.can_create_community_group_content, which also governs events.
  INSERT INTO public.community_group_challenges (
    id, group_id, creator_id, title, summary, metric, target_value,
    starts_at, ends_at, image_url, activity_config, challenge_kind,
    status, organizer_kind, organizer_user_id, scoring_mode,
    attempt_limit, route_verification_enabled, route_tolerance_meters,
    join_required
  )
  VALUES (
    p_id, p_group_id, v_actor, trim(p_title),
    left(coalesce(p_summary, ''), 800),
    p_metric, p_target_value, p_starts_at, p_ends_at,
    nullif(p_image_url, ''), null, 'weekly',
    'upcoming', 'group', null, 'cumulative',
    null, false, 100, true
  );

  INSERT INTO public.community_group_challenge_participants (
    group_id, challenge_id, user_id, status
  )
  VALUES (p_group_id, p_id, v_actor, 'joined')
  ON CONFLICT (challenge_id, user_id)
  DO UPDATE SET status = 'joined';

  -- New weekly challenges fill an empty or expired featured position.
  -- Never replace a currently active featured weekly goal.
  UPDATE public.community_groups g
  SET featured_challenge_id = p_id, updated_at = now()
  WHERE g.id = p_group_id
    AND (
      g.featured_challenge_id IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM public.community_group_challenges previous
        WHERE previous.id = g.featured_challenge_id
          AND previous.group_id = g.id
          AND previous.ends_at >= now()
          AND previous.status NOT IN ('cancelled', 'draft')
      )
    );

  RETURN p_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_community_group_weekly_challenge_v1(
  uuid,uuid,text,text,text,double precision,timestamptz,timestamptz,text,jsonb,jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_community_group_weekly_challenge_v1(
  uuid,uuid,text,text,text,double precision,timestamptz,timestamptz,text,jsonb,jsonb
) TO authenticated;

-- Prevent privilege escalation: only the Club creator/owner may
-- appoint, demote or remove another administrator. Admins still retain
-- management over contributors and regular members.
DROP POLICY IF EXISTS group_members_update_managers
  ON public.community_group_members;
CREATE POLICY group_members_update_managers
  ON public.community_group_members
  FOR UPDATE TO authenticated
  USING (
    role <> 'owner'
    AND private.can_manage_community_group(group_id)
    AND (
      role <> 'admin'
      OR EXISTS (
        SELECT 1 FROM public.community_groups g
        WHERE g.id = group_id AND g.creator_id = (SELECT auth.uid())
      )
    )
  )
  WITH CHECK (
    role IN ('admin', 'contributor', 'member')
    AND private.can_manage_community_group(group_id)
    AND (
      role <> 'admin'
      OR EXISTS (
        SELECT 1 FROM public.community_groups g
        WHERE g.id = group_id AND g.creator_id = (SELECT auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS group_members_remove_managers
  ON public.community_group_members;
CREATE POLICY group_members_remove_managers
  ON public.community_group_members
  FOR DELETE TO authenticated
  USING (
    role <> 'owner'
    AND private.can_manage_community_group(group_id)
    AND (
      role <> 'admin'
      OR EXISTS (
        SELECT 1 FROM public.community_groups g
        WHERE g.id = group_id AND g.creator_id = (SELECT auth.uid())
      )
    )
  );
