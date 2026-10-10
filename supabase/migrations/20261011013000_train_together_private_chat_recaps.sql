-- ATHLTH 1.7.1: private pre-workout chat and shared after-workout recap.
-- Only the host and accepted members may see either. No medical data included.

CREATE OR REPLACE FUNCTION private.can_view_train_together_circle(p_post_id uuid, p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, private
AS $$
  SELECT p_actor IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id = p_post_id
      AND (
        p.creator_id = p_actor
        OR EXISTS (
          SELECT 1 FROM public.train_together_requests r
          WHERE r.post_id = p.id AND r.requester_id = p_actor
            AND r.state = 'accepted'
        )
      )
  );
$$;
REVOKE ALL ON FUNCTION private.can_view_train_together_circle(uuid,uuid)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.can_view_train_together_circle(uuid,uuid)
TO authenticated;

CREATE TABLE IF NOT EXISTS public.train_together_post_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.train_together_posts(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  sender_display_name text NOT NULL
    CHECK (char_length(btrim(sender_display_name)) BETWEEN 1 AND 100),
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 800),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS train_together_post_messages_order
ON public.train_together_post_messages(post_id, created_at DESC);
ALTER TABLE public.train_together_post_messages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.train_together_post_messages FROM anon, authenticated;
GRANT SELECT, INSERT ON public.train_together_post_messages TO authenticated;
DROP POLICY IF EXISTS train_together_post_messages_read
ON public.train_together_post_messages;
CREATE POLICY train_together_post_messages_read
ON public.train_together_post_messages FOR SELECT TO authenticated
USING (private.can_view_train_together_circle(post_id, (SELECT auth.uid())));
DROP POLICY IF EXISTS train_together_post_messages_send
ON public.train_together_post_messages;
CREATE POLICY train_together_post_messages_send
ON public.train_together_post_messages FOR INSERT TO authenticated
WITH CHECK (
  sender_id = (SELECT auth.uid())
  AND private.can_view_train_together_circle(post_id, (SELECT auth.uid()))
  AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id=post_id AND p.status <> 'cancelled'
  )
);

CREATE TABLE IF NOT EXISTS public.train_together_recaps (
  post_id uuid PRIMARY KEY REFERENCES public.train_together_posts(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  note text NOT NULL DEFAULT '' CHECK (char_length(note) <= 1200),
  actual_minutes integer CHECK (actual_minutes IS NULL OR actual_minutes BETWEEN 1 AND 1440),
  actual_kilometers double precision CHECK (
    actual_kilometers IS NULL
    OR (actual_kilometers > 0 AND actual_kilometers <= 1000)
  ),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.train_together_recaps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.train_together_recaps FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.train_together_recaps TO authenticated;
DROP POLICY IF EXISTS train_together_recaps_read ON public.train_together_recaps;
CREATE POLICY train_together_recaps_read
ON public.train_together_recaps FOR SELECT TO authenticated
USING (private.can_view_train_together_circle(post_id, (SELECT auth.uid())));
DROP POLICY IF EXISTS train_together_recaps_insert ON public.train_together_recaps;
CREATE POLICY train_together_recaps_insert
ON public.train_together_recaps FOR INSERT TO authenticated
WITH CHECK (
  author_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id = post_id
      AND p.creator_id = (SELECT auth.uid())
      AND p.scheduled_start <= now()
      AND p.status <> 'cancelled'
  )
);
DROP POLICY IF EXISTS train_together_recaps_update ON public.train_together_recaps;
CREATE POLICY train_together_recaps_update
ON public.train_together_recaps FOR UPDATE TO authenticated
USING (
  author_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id = post_id AND p.creator_id = (SELECT auth.uid())
  )
)
WITH CHECK (
  author_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id = post_id AND p.creator_id = (SELECT auth.uid())
  )
);

CREATE TABLE IF NOT EXISTS public.train_together_recap_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.train_together_posts(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  storage_path text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS train_together_recap_photos_by_post
ON public.train_together_recap_photos(post_id, created_at);
ALTER TABLE public.train_together_recap_photos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.train_together_recap_photos FROM anon, authenticated;
GRANT SELECT, INSERT ON public.train_together_recap_photos TO authenticated;
DROP POLICY IF EXISTS train_together_recap_photos_read ON public.train_together_recap_photos;
CREATE POLICY train_together_recap_photos_read
ON public.train_together_recap_photos FOR SELECT TO authenticated
USING (private.can_view_train_together_circle(post_id, (SELECT auth.uid())));
DROP POLICY IF EXISTS train_together_recap_photos_insert ON public.train_together_recap_photos;
CREATE POLICY train_together_recap_photos_insert
ON public.train_together_recap_photos FOR INSERT TO authenticated
WITH CHECK (
  author_id = (SELECT auth.uid())
  AND storage_path LIKE post_id::text || '/' || author_id::text || '/%'
  AND private.can_view_train_together_circle(post_id, (SELECT auth.uid()))
  AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id=post_id AND p.scheduled_start <= now()
      AND p.status <> 'cancelled'
  )
);

INSERT INTO storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
VALUES ('train-together-recaps','train-together-recaps',false,3145728,ARRAY['image/jpeg'])
ON CONFLICT (id) DO UPDATE
SET public=false, file_size_limit=3145728,
    allowed_mime_types=ARRAY['image/jpeg'];
DROP POLICY IF EXISTS train_together_recap_storage_read ON storage.objects;
CREATE POLICY train_together_recap_storage_read
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id='train-together-recaps'
  AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id::text=(storage.foldername(name))[1]
      AND private.can_view_train_together_circle(p.id,(SELECT auth.uid()))
  )
);
DROP POLICY IF EXISTS train_together_recap_storage_upload ON storage.objects;
CREATE POLICY train_together_recap_storage_upload
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id='train-together-recaps'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1 FROM public.train_together_posts p
    WHERE p.id::text=(storage.foldername(name))[1]
      AND p.scheduled_start <= now()
      AND p.status <> 'cancelled'
      AND private.can_view_train_together_circle(p.id,(SELECT auth.uid()))
  )
);
-- Authors may remove only their own uploaded objects.
DROP POLICY IF EXISTS train_together_recap_storage_remove ON storage.objects;
CREATE POLICY train_together_recap_storage_remove
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id='train-together-recaps'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
);
