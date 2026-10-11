-- Arena collaboration v2: durable slots, inbox invitations, a real group chat,
-- and unanimous replacement after deletion. Existing Challenges untouched.
-- Personal identifiers are erased by FKs, but non-identifying series scores
-- remain attached to the slot. The deleting user's chat text is anonymized.

ALTER TABLE public.arena_series
  ALTER COLUMN owner_id DROP NOT NULL;
ALTER TABLE public.arena_series
  DROP CONSTRAINT IF EXISTS arena_series_owner_id_fkey;
ALTER TABLE public.arena_series
  ADD CONSTRAINT arena_series_owner_id_fkey
  FOREIGN KEY(owner_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.arena_series_members
  ADD COLUMN IF NOT EXISTS slot_id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS points numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS departed_at timestamptz,
  ADD COLUMN IF NOT EXISTS replaced_at timestamptz;
UPDATE public.arena_series_members SET slot_id = gen_random_uuid() WHERE slot_id IS NULL;
ALTER TABLE public.arena_series_members ALTER COLUMN slot_id SET NOT NULL;
ALTER TABLE public.arena_series_members DROP CONSTRAINT IF EXISTS arena_series_members_pkey;
ALTER TABLE public.arena_series_members ADD CONSTRAINT arena_series_members_pkey PRIMARY KEY (slot_id);
ALTER TABLE public.arena_series_members ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.arena_series_members DROP CONSTRAINT IF EXISTS arena_series_members_user_id_fkey;
ALTER TABLE public.arena_series_members
  ADD CONSTRAINT arena_series_members_user_id_fkey
  FOREIGN KEY(user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
ALTER TABLE public.arena_series_members DROP CONSTRAINT IF EXISTS arena_series_members_response_check;
ALTER TABLE public.arena_series_members ADD CONSTRAINT arena_series_members_response_check
  CHECK (response IN ('invited','accepted','declined','deleted'));
ALTER TABLE public.arena_series_members
  ADD CONSTRAINT arena_member_points_nonnegative CHECK (points >= 0);
CREATE UNIQUE INDEX IF NOT EXISTS arena_members_one_active_user
  ON public.arena_series_members(series_id,user_id) WHERE user_id IS NOT NULL;

ALTER TABLE public.arena_round_proposals ALTER COLUMN proposed_by DROP NOT NULL;
ALTER TABLE public.arena_round_proposals DROP CONSTRAINT IF EXISTS arena_round_proposals_proposed_by_fkey;
ALTER TABLE public.arena_round_proposals
  ADD CONSTRAINT arena_round_proposals_proposed_by_fkey
  FOREIGN KEY(proposed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- A missing user ID becomes an inert, display-only slot; points persist.
CREATE OR REPLACE FUNCTION private.arena_member_tombstone()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, public, private AS $$
BEGIN
  IF old.user_id IS NOT NULL AND new.user_id IS NULL THEN
    new.response := 'deleted';
    new.departed_at := now();
  END IF;
  RETURN new;
END;
$$;
DROP TRIGGER IF EXISTS arena_member_tombstone_before_update ON public.arena_series_members;
CREATE TRIGGER arena_member_tombstone_before_update
BEFORE UPDATE OF user_id ON public.arena_series_members
FOR EACH ROW EXECUTE FUNCTION private.arena_member_tombstone();

CREATE OR REPLACE FUNCTION private.arena_is_organizer(p_series uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
 SELECT (SELECT auth.uid()) IS NOT NULL AND (
   EXISTS (SELECT 1 FROM public.arena_series s
     WHERE s.id = p_series AND s.owner_id = (SELECT auth.uid()))
   OR EXISTS (
     SELECT 1 FROM public.arena_series s
     JOIN public.arena_series_members m ON m.series_id = s.id
     WHERE s.id = p_series AND s.owner_id IS NULL
       AND m.user_id = (SELECT auth.uid()) AND m.response = 'accepted'
       AND m.slot_id = (
         SELECT m2.slot_id FROM public.arena_series_members m2
          WHERE m2.series_id = p_series AND m2.response = 'accepted'
            AND m2.user_id IS NOT NULL
          ORDER BY m2.created_at, m2.slot_id LIMIT 1
       )
   )
 );
$$;
REVOKE ALL ON FUNCTION private.arena_is_organizer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.arena_is_organizer(uuid) TO authenticated;

-- Group chat is exclusive to accepted members, not a public Club message board.
CREATE TABLE IF NOT EXISTS public.arena_series_messages(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 series_id uuid NOT NULL REFERENCES public.arena_series(id) ON DELETE CASCADE,
 sender_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 2000),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS arena_series_messages_recent
  ON public.arena_series_messages(series_id,created_at DESC);
CREATE INDEX IF NOT EXISTS arena_series_messages_sender
  ON public.arena_series_messages(sender_id,created_at DESC);
ALTER TABLE public.arena_series_messages ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.arena_series_messages TO authenticated;
REVOKE ALL ON public.arena_series_messages FROM anon;

DROP POLICY IF EXISTS arena_series_chat_read ON public.arena_series_messages;
CREATE POLICY arena_series_chat_read ON public.arena_series_messages
FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.arena_series_members m WHERE m.series_id=arena_series_messages.series_id
   AND m.user_id=(SELECT auth.uid()) AND m.response='accepted')
);
DROP POLICY IF EXISTS arena_series_chat_post ON public.arena_series_messages;
CREATE POLICY arena_series_chat_post ON public.arena_series_messages
FOR INSERT TO authenticated WITH CHECK (
 sender_id=(SELECT auth.uid()) AND
 EXISTS(SELECT 1 FROM public.arena_series_members m
    WHERE m.series_id=arena_series_messages.series_id AND m.user_id=(SELECT auth.uid())
      AND m.response='accepted')
);

-- Extended kinds use the already-established social inbox and push pipeline.
ALTER TABLE public.social_inbox_events DROP CONSTRAINT IF EXISTS social_inbox_events_kind_check;
ALTER TABLE public.social_inbox_events
 ADD CONSTRAINT social_inbox_events_kind_check CHECK(kind IN (
 'friend_request','friend_accepted','follow_request','follow_accepted',
 'challenge_invite','challenge_result','challenge_accepted','challenge_declined',
 'challenge_withdrawn','reaction','workout_invite','workout_invite_accepted',
 'train_together_request','train_together_request_accepted','train_together_request_declined',
 'train_together_cancelled','train_together_chat','train_together_recap',
 'message','message_request','message_request_accepted','mention',
 'group_message','group_update','group_event','group_challenge','group_invite',
 'group_join_request','group_join_approved',
 'arena_invite','arena_chat','arena_replacement','arena_round'
 ));

CREATE OR REPLACE FUNCTION private.arena_send_invitation_to_inbox()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
DECLARE v_title text;
BEGIN
 IF new.response <> 'invited' OR new.user_id IS NULL THEN RETURN new; END IF;
 SELECT title INTO v_title FROM public.arena_series WHERE id=new.series_id;
 INSERT INTO public.social_inbox_events(
   recipient_id,kind,title,message,entity_type,entity_id,actor_id)
 SELECT new.user_id,'arena_invite','ATHLTH Arena',
   'Invitasjon til ' || left(v_title,80),
   'arena_series',new.series_id,s.owner_id
 FROM public.arena_series s WHERE s.id=new.series_id;
 RETURN new;
END; $$;
DROP TRIGGER IF EXISTS arena_invite_inbox ON public.arena_series_members;
CREATE TRIGGER arena_invite_inbox AFTER INSERT ON public.arena_series_members
FOR EACH ROW EXECUTE FUNCTION private.arena_send_invitation_to_inbox();

CREATE OR REPLACE FUNCTION private.arena_notify_chat()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
BEGIN
 INSERT INTO public.social_inbox_events(
   recipient_id,kind,title,message,entity_type,entity_id,actor_id)
 SELECT m.user_id,'arena_chat','Arena-gruppechat',
   left(new.body,140),'arena_series',new.series_id,new.sender_id
 FROM public.arena_series_members m
 WHERE m.series_id=new.series_id AND m.response='accepted'
   AND m.user_id IS NOT NULL AND m.user_id IS DISTINCT FROM new.sender_id;
 RETURN new;
END; $$;
DROP TRIGGER IF EXISTS arena_chat_notify ON public.arena_series_messages;
CREATE TRIGGER arena_chat_notify AFTER INSERT ON public.arena_series_messages
FOR EACH ROW EXECUTE FUNCTION private.arena_notify_chat();

-- Suppress authored chat content during account deletion, before the FK
-- unlink. No name, ID or text from a deleted athlete is retained in chat.
CREATE OR REPLACE FUNCTION private.arena_redact_deleted_messages()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
BEGIN
 UPDATE public.arena_series_messages SET body='Melding fra slettet bruker'
  WHERE sender_id=old.id;
 RETURN old;
END; $$;
DROP TRIGGER IF EXISTS arena_redact_profile_messages ON public.profiles;
CREATE TRIGGER arena_redact_profile_messages BEFORE DELETE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION private.arena_redact_deleted_messages();

-- Replacement is separate from invitees and does not require a new series.
CREATE TABLE IF NOT EXISTS public.arena_replacement_proposals(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 series_id uuid NOT NULL REFERENCES public.arena_series(id) ON DELETE CASCADE,
 slot_id uuid NOT NULL REFERENCES public.arena_series_members(slot_id) ON DELETE CASCADE,
 proposed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 nominee_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
 status text NOT NULL DEFAULT 'pending'
   CHECK(status IN ('pending','approved','rejected','cancelled')),
 created_at timestamptz NOT NULL DEFAULT now(),
 decided_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS arena_replacement_one_pending
 ON public.arena_replacement_proposals(slot_id) WHERE status='pending';
CREATE INDEX IF NOT EXISTS arena_replacement_series
 ON public.arena_replacement_proposals(series_id,created_at DESC);
CREATE INDEX IF NOT EXISTS arena_replacement_nominee
 ON public.arena_replacement_proposals(nominee_id,status);
CREATE TABLE IF NOT EXISTS public.arena_replacement_votes(
 proposal_id uuid NOT NULL REFERENCES public.arena_replacement_proposals(id) ON DELETE CASCADE,
 voter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
 accepted boolean NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(proposal_id,voter_id)
);
CREATE INDEX IF NOT EXISTS arena_replacement_voter ON public.arena_replacement_votes(voter_id);
ALTER TABLE public.arena_replacement_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arena_replacement_votes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.arena_replacement_proposals,public.arena_replacement_votes FROM anon,authenticated;
GRANT SELECT ON public.arena_replacement_proposals,public.arena_replacement_votes TO authenticated;

DROP POLICY IF EXISTS arena_replacement_view ON public.arena_replacement_proposals;
CREATE POLICY arena_replacement_view ON public.arena_replacement_proposals
FOR SELECT TO authenticated USING (
 private.arena_can_access(series_id) OR nominee_id=(SELECT auth.uid())
);
DROP POLICY IF EXISTS arena_replacement_votes_view ON public.arena_replacement_votes;
CREATE POLICY arena_replacement_votes_view ON public.arena_replacement_votes
FOR SELECT TO authenticated USING (
 EXISTS(SELECT 1 FROM public.arena_replacement_proposals p
    WHERE p.id=proposal_id
      AND (private.arena_can_access(p.series_id) OR p.nominee_id=(SELECT auth.uid())))
);

-- Security-definer RPCs below explicitly validate caller, nominee and scope.
-- No direct client UPDATE/DELETE on slots, points or proposals is granted.
CREATE OR REPLACE FUNCTION public.arena_propose_replacement(
 p_slot uuid,p_nominee uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
DECLARE v_slot public.arena_series_members%rowtype;
 v_id uuid;
BEGIN
 SELECT * INTO v_slot FROM public.arena_series_members WHERE slot_id=p_slot FOR UPDATE;
 IF NOT FOUND OR v_slot.user_id IS NOT NULL OR v_slot.response <> 'deleted' THEN
   RAISE EXCEPTION 'Only deleted member slots can be replaced';
 END IF;
 IF NOT private.arena_is_organizer(v_slot.series_id) THEN
   RAISE EXCEPTION 'Only the series organizer can propose a replacement';
 END IF;
 IF NOT private.arena_can_invite(p_nominee) THEN
   RAISE EXCEPTION 'The nominee cannot be invited';
 END IF;
 IF EXISTS(SELECT 1 FROM public.arena_series_members WHERE series_id=v_slot.series_id
           AND user_id=p_nominee) THEN
   RAISE EXCEPTION 'Nominee is already a series member';
 END IF;
 INSERT INTO public.arena_replacement_proposals(series_id,slot_id,proposed_by,nominee_id)
 VALUES(v_slot.series_id,p_slot,(SELECT auth.uid()),p_nominee) RETURNING id INTO v_id;
 INSERT INTO public.social_inbox_events(
  recipient_id,kind,title,message,entity_type,entity_id,actor_id)
 SELECT voter,'arena_replacement','Arena - bytte av deltaker',
    'Forslag til å overta en slettet plass','arena_series',v_slot.series_id,(SELECT auth.uid())
 FROM (
   SELECT m.user_id AS voter FROM public.arena_series_members m
   WHERE m.series_id=v_slot.series_id AND m.response='accepted' AND m.user_id IS NOT NULL
   UNION SELECT p_nominee
 ) recipients;
 RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.arena_vote_replacement(
 p_proposal uuid,p_accept boolean
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private AS $$
DECLARE v_prop public.arena_replacement_proposals%rowtype;
 v_actor uuid:=(SELECT auth.uid());
 v_needed int;
 v_approved int;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'Sign in required'; END IF;
 SELECT * INTO v_prop FROM public.arena_replacement_proposals
 WHERE id=p_proposal FOR UPDATE;
 IF NOT FOUND OR v_prop.status <> 'pending' OR v_prop.nominee_id IS NULL THEN
   RAISE EXCEPTION 'Replacement proposal is not pending';
 END IF;
 IF NOT (
   v_actor=v_prop.nominee_id
   OR EXISTS(SELECT 1 FROM public.arena_series_members m
     WHERE m.series_id=v_prop.series_id AND m.user_id=v_actor
       AND m.response='accepted')
 ) THEN
    RAISE EXCEPTION 'You are not eligible to vote';
 END IF;
 IF EXISTS(SELECT 1 FROM public.arena_replacement_votes v
    WHERE v.proposal_id=p_proposal AND v.voter_id=v_actor) THEN
   RAISE EXCEPTION 'Vote already recorded';
 END IF;
 INSERT INTO public.arena_replacement_votes(proposal_id,voter_id,accepted)
 VALUES(p_proposal,v_actor,p_accept);
 IF NOT p_accept THEN
   UPDATE public.arena_replacement_proposals
   SET status='rejected',decided_at=now() WHERE id=p_proposal;
   RETURN 'rejected';
 END IF;
 SELECT count(*)+1 INTO v_needed
 FROM public.arena_series_members m WHERE m.series_id=v_prop.series_id
   AND m.response='accepted' AND m.user_id IS NOT NULL;
 SELECT count(*) INTO v_approved
 FROM public.arena_replacement_votes v WHERE v.proposal_id=p_proposal AND v.accepted;
 IF v_approved=v_needed
   AND EXISTS(SELECT 1 FROM public.arena_replacement_votes v
     WHERE v.proposal_id=p_proposal AND v.voter_id=v_prop.nominee_id
       AND v.accepted)
   AND NOT EXISTS(SELECT 1 FROM public.arena_series_members m
     WHERE m.series_id=v_prop.series_id AND m.user_id=v_prop.nominee_id)
 THEN
   UPDATE public.arena_series_members
   SET user_id=v_prop.nominee_id,response='accepted',replaced_at=now()
   WHERE slot_id=v_prop.slot_id AND user_id IS NULL AND response='deleted';
   IF NOT FOUND THEN RAISE EXCEPTION 'Unavailable competition slot'; END IF;
   UPDATE public.arena_replacement_proposals SET status='approved',decided_at=now()
     WHERE id=p_proposal;
   RETURN 'approved';
 END IF;
 RETURN 'pending';
END; $$;

REVOKE ALL ON FUNCTION public.arena_propose_replacement(uuid,uuid)
 FROM public,anon;
REVOKE ALL ON FUNCTION public.arena_vote_replacement(uuid,boolean)
 FROM public,anon;
GRANT EXECUTE ON FUNCTION public.arena_propose_replacement(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.arena_vote_replacement(uuid,boolean) TO authenticated;
REVOKE ALL ON FUNCTION private.arena_notify_chat() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.arena_send_invitation_to_inbox() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.arena_redact_deleted_messages() FROM PUBLIC,anon,authenticated;


-- Nominees may inspect the series and rules before accepting the inherited
-- score/slot, but cannot post or vote on ordinary rounds until replacement.
CREATE OR REPLACE FUNCTION private.arena_can_access(p_series_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
 SELECT (SELECT auth.uid()) IS NOT NULL AND (
  EXISTS(SELECT 1 FROM public.arena_series s
         WHERE s.id=p_series_id AND s.owner_id=(SELECT auth.uid()))
  OR EXISTS(SELECT 1 FROM public.arena_series_members m
        WHERE m.series_id=p_series_id AND m.user_id=(SELECT auth.uid())
          AND m.response IN ('invited','accepted'))
  OR EXISTS(SELECT 1 FROM public.arena_replacement_proposals p
        WHERE p.series_id=p_series_id AND p.nominee_id=(SELECT auth.uid())
          AND p.status='pending')
 );
$$;
REVOKE ALL ON FUNCTION private.arena_can_access(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.arena_can_access(uuid) TO authenticated;
