-- ATHLTH 1.7.1: keep curated weekly Club challenges separate from
-- member-created route and activity challenges, without copying workouts.
ALTER TABLE public.community_group_challenges
  ADD COLUMN IF NOT EXISTS challenge_kind text NOT NULL DEFAULT 'standard';

ALTER TABLE public.community_group_challenges
  DROP CONSTRAINT IF EXISTS community_group_challenge_kind_check;
ALTER TABLE public.community_group_challenges
  ADD CONSTRAINT community_group_challenge_kind_check
  CHECK (challenge_kind IN ('standard', 'weekly'));

-- Preserve Clubs' previously selected featured challenges.
UPDATE public.community_group_challenges c
SET challenge_kind = 'weekly'
FROM public.community_groups g
WHERE g.featured_challenge_id = c.id
  AND g.id = c.group_id
  AND c.challenge_kind = 'standard';

CREATE INDEX IF NOT EXISTS community_group_challenges_kind_idx
  ON public.community_group_challenges (group_id, challenge_kind, starts_at);

-- A contributor can publish a weekly challenge, but ordinary members
-- cannot relabel a normal challenge to get elevated presentation rights.
CREATE OR REPLACE FUNCTION private.guard_group_challenge_kind()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private'
AS $function$
DECLARE
  v_actor uuid := (SELECT auth.uid());
  v_is_publisher boolean := false;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.challenge_kind = 'standard' THEN
      RETURN NEW;
    END IF;
  ELSIF NEW.challenge_kind IS NOT DISTINCT FROM OLD.challenge_kind THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.community_groups g
    LEFT JOIN public.community_group_members m
      ON m.group_id = g.id AND m.user_id = v_actor
    WHERE g.id = NEW.group_id
      AND (g.creator_id = v_actor OR m.role IN ('owner', 'admin', 'contributor'))
  ) INTO v_is_publisher;

  IF NOT v_is_publisher THEN
    RAISE EXCEPTION 'Only Club managers and contributors can change the weekly challenge type';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS guard_group_challenge_kind
ON public.community_group_challenges;
CREATE TRIGGER guard_group_challenge_kind
BEFORE INSERT OR UPDATE OF challenge_kind
ON public.community_group_challenges
FOR EACH ROW
EXECUTE FUNCTION private.guard_group_challenge_kind();

-- Weekly challenges reuse the existing scoring/verification engine, but
-- get a separate category and a restricted server-side creation endpoint.
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
    SELECT 1
    FROM public.community_groups g
    LEFT JOIN public.community_group_members m
      ON m.group_id = g.id AND m.user_id = v_actor
    WHERE g.id = p_group_id
      AND (g.creator_id = v_actor OR m.role IN ('owner', 'admin', 'contributor'))
  ) THEN
    RAISE EXCEPTION 'Only owners, admins and contributors can create weekly Club challenges';
  END IF;

  IF p_metric NOT IN ('workouts', 'distance_km', 'active_minutes') THEN
    RAISE EXCEPTION 'Weekly Club challenges support workouts, distance or training minutes';
  END IF;

  IF p_activity_config IS NOT NULL THEN
    RAISE EXCEPTION 'Route-specific challenges belong in New challenge';
  END IF;

  -- Existing RPC validates the target, dates, joins and ordinary permissions.
  PERFORM public.create_community_group_challenge_v2(
    p_id, p_group_id, p_title, p_summary, p_metric,
    p_target_value, p_starts_at, p_ends_at, p_image_url,
    p_activity_config, p_options
  );

  UPDATE public.community_group_challenges
  SET challenge_kind = 'weekly'
  WHERE id = p_id AND group_id = p_group_id AND creator_id = v_actor;

  -- Fill an empty/expired weekly feature automatically. Do not replace
  -- an active feature when a contributor schedules another one.
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

-- A featured challenge must belong to the Club and be categorized weekly.
CREATE OR REPLACE FUNCTION private.guard_club_weekly_feature()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public', 'private'
AS $function$
BEGIN
  IF NEW.featured_challenge_id IS NOT NULL
     AND NEW.featured_challenge_id IS DISTINCT FROM OLD.featured_challenge_id
     AND NOT EXISTS (
       SELECT 1 FROM public.community_group_challenges c
       WHERE c.id = NEW.featured_challenge_id
         AND c.group_id = NEW.id
         AND c.challenge_kind = 'weekly'
     )
  THEN
    RAISE EXCEPTION 'Only weekly Club challenges can be featured';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS guard_club_weekly_feature
ON public.community_groups;
CREATE TRIGGER guard_club_weekly_feature
BEFORE UPDATE OF featured_challenge_id
ON public.community_groups
FOR EACH ROW
EXECUTE FUNCTION private.guard_club_weekly_feature();
