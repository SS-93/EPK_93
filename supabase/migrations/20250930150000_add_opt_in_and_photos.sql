-- ===============================================
-- FEATURE REQUEST: Voting/Scoring Opt-In & Artist Photos
-- ===============================================
-- Part 1: Add opt-in fields for event participants
-- Part 2: Add photo upload capability for artists and map to trading cards

-- ===============================================
-- PART 1: EVENT PARTICIPANT OPT-IN FIELDS
-- ===============================================

-- Add opt-in fields to event_participants table
ALTER TABLE event_participants
ADD COLUMN IF NOT EXISTS allow_voting BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS allow_scoring BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS consent_timestamp TIMESTAMPTZ;

-- Add comment for clarity
COMMENT ON COLUMN event_participants.allow_voting IS 'User consent to participate in voting for artists';
COMMENT ON COLUMN event_participants.allow_scoring IS 'User consent to participate in scoring/rating artists';
COMMENT ON COLUMN event_participants.consent_timestamp IS 'When user provided consent for voting/scoring';

-- Create index for filtering participants by consent
CREATE INDEX IF NOT EXISTS idx_event_participants_voting_consent
ON event_participants(event_id, allow_voting)
WHERE allow_voting = true;

CREATE INDEX IF NOT EXISTS idx_event_participants_scoring_consent
ON event_participants(event_id, allow_scoring)
WHERE allow_scoring = true;

-- ===============================================
-- PART 2: ARTIST PHOTO UPLOAD SYSTEM
-- ===============================================

-- Add photo storage fields to artist_profiles table
ALTER TABLE artist_profiles
ADD COLUMN IF NOT EXISTS profile_photos JSONB DEFAULT '[]', -- Array of photo objects
ADD COLUMN IF NOT EXISTS primary_photo_url TEXT, -- Main profile photo
ADD COLUMN IF NOT EXISTS gallery_updated_at TIMESTAMPTZ;

-- JSONB structure for profile_photos:
-- [
--   {
--     "id": "uuid",
--     "url": "supabase_storage_url",
--     "uploaded_at": "timestamp",
--     "is_primary": boolean,
--     "caption": "optional text",
--     "metadata": { "width": 1200, "height": 1200, "format": "jpg" }
--   }
-- ]

COMMENT ON COLUMN artist_profiles.profile_photos IS 'Array of artist photo objects with metadata';
COMMENT ON COLUMN artist_profiles.primary_photo_url IS 'URL to primary profile photo used in trading cards';
COMMENT ON COLUMN artist_profiles.gallery_updated_at IS 'Last time photo gallery was updated';

-- Create index for querying artists with photos
CREATE INDEX IF NOT EXISTS idx_artist_profiles_has_photos
ON artist_profiles((profile_photos::text != '[]'))
WHERE profile_photos::text != '[]';

-- ===============================================
-- STORAGE BUCKET FOR ARTIST PHOTOS
-- ===============================================

-- Create storage bucket for artist photos (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'artist-photos',
  'artist-photos',
  true, -- Public access for trading cards
  5242880, -- 5MB max file size
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[];

-- RLS policies for artist-photos bucket
-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Artists can upload their own photos" ON storage.objects;
DROP POLICY IF EXISTS "Artists can update their own photos" ON storage.objects;
DROP POLICY IF EXISTS "Artists can delete their own photos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view artist photos" ON storage.objects;

-- Create new policies
CREATE POLICY "Artists can upload their own photos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'artist-photos' AND
  (storage.foldername(name))[1] = (
    SELECT id::text FROM artist_profiles WHERE user_id = auth.uid()
  )
);

CREATE POLICY "Artists can update their own photos"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'artist-photos' AND
  (storage.foldername(name))[1] = (
    SELECT id::text FROM artist_profiles WHERE user_id = auth.uid()
  )
);

CREATE POLICY "Artists can delete their own photos"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'artist-photos' AND
  (storage.foldername(name))[1] = (
    SELECT id::text FROM artist_profiles WHERE user_id = auth.uid()
  )
);

CREATE POLICY "Anyone can view artist photos"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'artist-photos');

-- ===============================================
-- HELPER FUNCTIONS
-- ===============================================

-- Function to get artist primary photo URL (with fallback)
CREATE OR REPLACE FUNCTION get_artist_photo_url(artist_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  photo_url TEXT;
  fallback_url TEXT;
BEGIN
  -- Try to get primary_photo_url first
  SELECT primary_photo_url INTO photo_url
  FROM artist_profiles
  WHERE id = artist_id;

  -- If no primary photo, try to get first photo from gallery
  IF photo_url IS NULL THEN
    SELECT (profile_photos->0->>'url')::text INTO photo_url
    FROM artist_profiles
    WHERE id = artist_id
    AND jsonb_array_length(profile_photos) > 0;
  END IF;

  -- If still no photo, check old profile_image_url column (backward compatibility)
  IF photo_url IS NULL THEN
    SELECT ap.profile_image_url INTO photo_url
    FROM artist_profiles ap
    WHERE ap.id = artist_id;
  END IF;

  -- If still no photo, use user avatar from profiles table
  IF photo_url IS NULL THEN
    SELECT p.avatar_url INTO photo_url
    FROM artist_profiles ap
    JOIN profiles p ON ap.user_id = p.id
    WHERE ap.id = artist_id;
  END IF;

  -- Return photo URL or NULL (component will show fallback avatar)
  RETURN photo_url;
END;
$$;

-- Function to update primary photo
CREATE OR REPLACE FUNCTION set_artist_primary_photo(artist_id UUID, photo_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update primary_photo_url
  UPDATE artist_profiles
  SET
    primary_photo_url = photo_url,
    gallery_updated_at = now()
  WHERE id = artist_id;

  -- Update is_primary flag in profile_photos array
  UPDATE artist_profiles
  SET profile_photos = (
    SELECT jsonb_agg(
      CASE
        WHEN elem->>'url' = photo_url
        THEN jsonb_set(elem, '{is_primary}', 'true'::jsonb)
        ELSE jsonb_set(elem, '{is_primary}', 'false'::jsonb)
      END
    )
    FROM jsonb_array_elements(profile_photos) elem
  )
  WHERE id = artist_id;
END;
$$;

-- Function to add photo to artist gallery
CREATE OR REPLACE FUNCTION add_artist_photo(
  artist_id UUID,
  photo_url TEXT,
  caption TEXT DEFAULT NULL,
  set_as_primary BOOLEAN DEFAULT false
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  photo_id UUID;
  new_photo JSONB;
BEGIN
  photo_id := gen_random_uuid();

  new_photo := jsonb_build_object(
    'id', photo_id,
    'url', photo_url,
    'uploaded_at', now(),
    'is_primary', set_as_primary,
    'caption', caption
  );

  -- Add photo to gallery
  UPDATE artist_profiles
  SET
    profile_photos = profile_photos || new_photo,
    gallery_updated_at = now()
  WHERE id = artist_id;

  -- If set as primary, update primary_photo_url
  IF set_as_primary THEN
    PERFORM set_artist_primary_photo(artist_id, photo_url);
  END IF;

  RETURN photo_id;
END;
$$;

-- Function to remove photo from gallery
CREATE OR REPLACE FUNCTION remove_artist_photo(artist_id UUID, photo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  photo_url TEXT;
  was_primary BOOLEAN;
BEGIN
  -- Get photo info before deletion
  SELECT
    elem->>'url',
    (elem->>'is_primary')::boolean
  INTO photo_url, was_primary
  FROM artist_profiles,
       jsonb_array_elements(profile_photos) elem
  WHERE artist_profiles.id = artist_id
  AND elem->>'id' = photo_id::text;

  -- Remove photo from array
  UPDATE artist_profiles
  SET
    profile_photos = (
      SELECT jsonb_agg(elem)
      FROM jsonb_array_elements(profile_photos) elem
      WHERE elem->>'id' != photo_id::text
    ),
    gallery_updated_at = now()
  WHERE id = artist_id;

  -- If this was the primary photo, set first remaining photo as primary
  IF was_primary THEN
    UPDATE artist_profiles
    SET primary_photo_url = (profile_photos->0->>'url')::text
    WHERE id = artist_id;
  END IF;
END;
$$;

-- ===============================================
-- UPDATE EXISTING VIEWS/MATERIALIZED VIEWS
-- ===============================================

-- Create view for event artists with photos
-- Handle both possible column names (artist_profile_id or artist_id)
DO $$
DECLARE
  col_name TEXT;
BEGIN
  -- Check which column exists
  SELECT column_name INTO col_name
  FROM information_schema.columns
  WHERE table_name = 'event_artists'
  AND column_name IN ('artist_profile_id', 'artist_id')
  LIMIT 1;

  IF col_name IS NULL THEN
    RAISE NOTICE 'Warning: event_artists table not found or has no artist reference column';
    RETURN;
  END IF;

  -- Create view with the correct column name
  IF col_name = 'artist_profile_id' THEN
    EXECUTE '
      CREATE OR REPLACE VIEW event_artists_with_photos AS
      SELECT
        ea.*,
        get_artist_photo_url(ea.artist_profile_id) as artist_photo_url,
        ap.artist_name,
        ap.bio,
        ap.social_links,
        ap.verification_status
      FROM event_artists ea
      JOIN artist_profiles ap ON ea.artist_profile_id = ap.id
    ';
  ELSE
    EXECUTE '
      CREATE OR REPLACE VIEW event_artists_with_photos AS
      SELECT
        ea.*,
        get_artist_photo_url(ea.artist_id) as artist_photo_url,
        ap.artist_name,
        ap.bio,
        ap.social_links,
        ap.verification_status
      FROM event_artists ea
      JOIN artist_profiles ap ON ea.artist_id = ap.id
    ';
  END IF;

  RAISE NOTICE 'Created view using column: %', col_name;
END $$;

-- Grant select permissions on view (only if it exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_views WHERE viewname = 'event_artists_with_photos') THEN
    GRANT SELECT ON event_artists_with_photos TO authenticated, anon;
    RAISE NOTICE 'Granted permissions on event_artists_with_photos view';
  ELSE
    RAISE NOTICE 'Skipping grant - event_artists_with_photos view does not exist';
  END IF;
END $$;

-- ===============================================
-- VALIDATION CONSTRAINTS
-- ===============================================

-- Ensure at least one opt-in is true if participant is registered
ALTER TABLE event_participants
ADD CONSTRAINT check_at_least_one_consent
CHECK (allow_voting = true OR allow_scoring = true);

-- Ensure profile_photos is valid JSON array
ALTER TABLE artist_profiles
ADD CONSTRAINT check_profile_photos_is_array
CHECK (jsonb_typeof(profile_photos) = 'array');

-- ===============================================
-- MIGRATION NOTES
-- ===============================================

-- Backfill existing participants with default opt-ins
UPDATE event_participants
SET
  allow_voting = true,
  allow_scoring = true,
  consent_timestamp = created_at
WHERE allow_voting IS NULL OR allow_scoring IS NULL;

-- Backfill existing artist photos (only if profile_image_url column exists)
DO $$
DECLARE
  artist RECORD;
  photo_id UUID;
  has_profile_image_col BOOLEAN;
BEGIN
  -- Check if profile_image_url column exists
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'artist_profiles'
    AND column_name = 'profile_image_url'
  ) INTO has_profile_image_col;

  IF NOT has_profile_image_col THEN
    RAISE NOTICE 'Skipping photo backfill - profile_image_url column does not exist';
    RETURN;
  END IF;

  -- Backfill existing photos
  FOR artist IN
    EXECUTE '
      SELECT id, profile_image_url
      FROM artist_profiles
      WHERE profile_image_url IS NOT NULL
      AND (profile_photos IS NULL OR profile_photos = ''[]''::jsonb)
    '
  LOOP
    photo_id := gen_random_uuid();

    UPDATE artist_profiles
    SET
      profile_photos = jsonb_build_array(
        jsonb_build_object(
          'id', photo_id,
          'url', artist.profile_image_url,
          'uploaded_at', now(),
          'is_primary', true,
          'caption', 'Profile Photo'
        )
      ),
      primary_photo_url = artist.profile_image_url,
      gallery_updated_at = now()
    WHERE id = artist.id;
  END LOOP;

  RAISE NOTICE 'Backfilled photos for existing artists';
END $$;

-- ===============================================
-- TESTING QUERIES
-- ===============================================

-- Test: Get artist with photo for trading card
-- SELECT
--   artist_name,
--   get_artist_photo_url(id) as photo_url,
--   profile_photos
-- FROM artist_profiles
-- LIMIT 5;

-- Test: Get participants who opted in for voting
-- SELECT
--   name,
--   email,
--   allow_voting,
--   allow_scoring
-- FROM event_participants
-- WHERE event_id = 'YOUR_EVENT_ID'
-- AND allow_voting = true;