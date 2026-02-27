-- Add media fields to events table for banner photos and videos

ALTER TABLE events
ADD COLUMN IF NOT EXISTS video_url TEXT,
ADD COLUMN IF NOT EXISTS video_thumbnail_url TEXT,
ADD COLUMN IF NOT EXISTS banner_settings JSONB DEFAULT '{"applyToBackground": false, "overlayOpacity": 0.5}';

-- Add comments
COMMENT ON COLUMN events.video_url IS 'URL to event promo/highlight video';
COMMENT ON COLUMN events.video_thumbnail_url IS 'Thumbnail for video player';
COMMENT ON COLUMN events.banner_settings IS 'Settings for banner display: applyToBackground, overlayOpacity, etc.';

-- Create storage bucket for event media if not exists
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'event-media',
  'event-media',
  true,
  52428800, -- 50MB for videos
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'video/mp4', 'video/webm', 'video/mov']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 52428800,
  allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'video/mp4', 'video/webm', 'video/mov']::text[];

-- RLS policies for event-media bucket
DROP POLICY IF EXISTS "Event hosts can upload event media" ON storage.objects;
DROP POLICY IF EXISTS "Event hosts can update event media" ON storage.objects;
DROP POLICY IF EXISTS "Event hosts can delete event media" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view event media" ON storage.objects;

CREATE POLICY "Event hosts can upload event media"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'event-media' AND
  (storage.foldername(name))[1] IN (
    SELECT id::text FROM events WHERE host_user_id = auth.uid()
  )
);

CREATE POLICY "Event hosts can update event media"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'event-media' AND
  (storage.foldername(name))[1] IN (
    SELECT id::text FROM events WHERE host_user_id = auth.uid()
  )
);

CREATE POLICY "Event hosts can delete event media"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'event-media' AND
  (storage.foldername(name))[1] IN (
    SELECT id::text FROM events WHERE host_user_id = auth.uid()
  )
);

CREATE POLICY "Anyone can view event media"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'event-media');
