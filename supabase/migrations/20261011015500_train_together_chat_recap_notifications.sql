-- ATHLTH 1.7.1: notification events for accepted Train Together groups.
-- Notification text never contains private chat content or location.

ALTER TABLE public.social_inbox_events
  DROP CONSTRAINT IF EXISTS social_inbox_events_kind_check;
ALTER TABLE public.social_inbox_events
  ADD CONSTRAINT social_inbox_events_kind_check CHECK (
    kind IN (
      'friend_request','friend_accepted','follow_request','follow_accepted',
      'challenge_invite','challenge_result','challenge_accepted',
      'challenge_declined','challenge_withdrawn','reaction',
      'workout_invite','workout_invite_accepted',
      'train_together_request','train_together_request_accepted',
      'train_together_request_declined','train_together_cancelled',
      'train_together_chat','train_together_recap',
      'message','message_request','message_request_accepted','mention',
      'group_message','group_update','group_event','group_challenge',
      'group_invite','group_join_request','group_join_approved'
    )
  );

CREATE OR REPLACE FUNCTION private.notify_train_together_chat()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_title text;
  v_recipient uuid;
BEGIN
  SELECT title INTO v_title
    FROM public.train_together_posts WHERE id = NEW.post_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  FOR v_recipient IN
    SELECT p.creator_id
    FROM public.train_together_posts p WHERE p.id = NEW.post_id
    UNION
    SELECT r.requester_id
    FROM public.train_together_requests r
    WHERE r.post_id = NEW.post_id AND r.state = 'accepted'
  LOOP
    IF v_recipient = NEW.sender_id THEN CONTINUE; END IF;

    -- Collapse rapid consecutive messages to avoid notification flooding.
    IF EXISTS (
      SELECT 1 FROM public.social_inbox_events e
      WHERE e.recipient_id = v_recipient
        AND e.kind = 'train_together_chat'
        AND e.entity_id = NEW.post_id
        AND e.created_at > now() - interval '3 minutes'
        AND e.read_at IS NULL
    ) THEN CONTINUE; END IF;

    INSERT INTO public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    ) VALUES (
      v_recipient, NEW.sender_id, 'train_together_chat',
      'New workout group message', 'New message in ' || left(v_title, 100),
      'train_together_post', NEW.post_id
    );
  END LOOP;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_train_together_chat
ON public.train_together_post_messages;
CREATE TRIGGER notify_train_together_chat
AFTER INSERT ON public.train_together_post_messages
FOR EACH ROW EXECUTE FUNCTION private.notify_train_together_chat();

CREATE OR REPLACE FUNCTION private.notify_train_together_recap()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $function$
DECLARE
  v_recipient uuid;
  v_title text;
BEGIN
  SELECT title INTO v_title
  FROM public.train_together_posts WHERE id=NEW.post_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  FOR v_recipient IN
    SELECT requester_id FROM public.train_together_requests
    WHERE post_id=NEW.post_id AND state='accepted'
  LOOP
    INSERT INTO public.social_inbox_events (
      recipient_id, actor_id, kind, title, message, entity_type, entity_id
    ) VALUES (
      v_recipient, NEW.author_id, 'train_together_recap',
      'Shared workout recap', 'The recap for ' || left(v_title, 100) || ' is ready.',
      'train_together_post', NEW.post_id
    );
  END LOOP;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS notify_train_together_recap
ON public.train_together_recaps;
CREATE TRIGGER notify_train_together_recap
AFTER INSERT ON public.train_together_recaps
FOR EACH ROW EXECUTE FUNCTION private.notify_train_together_recap();
