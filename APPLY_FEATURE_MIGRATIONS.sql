-- ===============================================
-- FEATURE REQUEST MIGRATIONS - MANUAL APPLICATION
-- ===============================================
-- Run these migrations in Supabase Dashboard SQL Editor
-- Copy and paste the entire contents into the SQL Editor

-- ===============================================
-- MIGRATION 1: MediaID Role and Trigger Fix
-- ===============================================

-- Step 1: Add role column to media_ids if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='media_ids' AND column_name='role') THEN
        ALTER TABLE media_ids
        ADD COLUMN role user_role NOT NULL DEFAULT 'fan',
        ADD COLUMN version INTEGER DEFAULT 1,
        ADD COLUMN is_active BOOLEAN DEFAULT true;

        RAISE NOTICE 'Added role, version, and is_active columns to media_ids';
    ELSE
        RAISE NOTICE 'role column already exists in media_ids';
    END IF;
END $$;

-- Step 2: Create or replace the handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- Create profile
  INSERT INTO public.profiles (id, display_name, role, email_verified, onboarding_completed)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'fan'),
    NEW.email_confirmed_at IS NOT NULL,
    false
  )
  ON CONFLICT (id) DO NOTHING;

  -- Create MediaID with role field
  INSERT INTO public.media_ids (user_uuid, role, interests, genre_preferences, privacy_settings, version, is_active)
  VALUES (
    NEW.id,
    COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'fan'),
    '{}',
    '{}',
    jsonb_build_object(
      'data_sharing', true,
      'location_access', false,
      'audio_capture', false,
      'anonymous_logging', true,
      'marketing_communications', false
    ),
    1,
    true
  )
  ON CONFLICT (user_uuid) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail signup
    RAISE WARNING 'Error in handle_new_user for %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Create the trigger (drop first if exists)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 4: Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON public.profiles TO authenticated;
GRANT ALL ON public.media_ids TO authenticated;
GRANT SELECT ON public.profiles TO anon;
GRANT SELECT ON public.media_ids TO anon;

-- ===============================================
-- MIGRATION 2: Voting/Scoring Opt-In & Artist Photos
-- ===============================================

-- PART 1: EVENT PARTICIPANT OPT-IN FIELDS
-- Add opt-in fields to event_participants table
ALTER TABLE event_participants
ADD COLUMN IF NOT EXISTS allow_voting BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS allow_scoring BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS consent_timestamp TIMESTAMPTZ;

-- Add comments for clarity
COMMENT ON COLUMN event_participants.allow_voting IS 'User consent to participate in voting for artists';
COMMENT ON COLUMN event_participants.allow_scoring IS 'User consent to participate in scoring/rating artists';
COMMENT ON COLUMN event_participants.consent_timestamp IS 'When user provided consent for voting/scoring';

-- Create indexes for filtering participants by consent
CREATE INDEX IF NOT EXISTS idx_event_participants_voting_consent
ON event_participants(event_id, allow_voting)
WHERE allow_voting = true;

CREATE INDEX IF NOT EXISTS idx_event_participants_scoring_consent
ON event_participants(event_id, allow_scoring)
WHERE allow_scoring = true;

-- Ensure at least one opt-in is true if participant is registered
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'check_at_least_one_consent'
  ) THEN
    ALTER TABLE event_participants
    ADD CONSTRAINT check_at_least_one_consent
    CHECK (allow_voting = true OR allow_scoring = true);
  END IF;
END $$;

-- Backfill existing participants with default opt-ins
UPDATE event_participants
SET
  allow_voting = true,
  allow_scoring = true,
  consent_timestamp = created_at
WHERE allow_voting IS NULL OR allow_scoring IS NULL;

-- PART 2: ARTIST PHOTO UPLOAD SYSTEM
-- Add photo storage fields to artist_profiles table
ALTER TABLE artist_profiles
ADD COLUMN IF NOT EXISTS profile_photos JSONB DEFAULT '[]', -- Array of photo objects
ADD COLUMN IF NOT EXISTS primary_photo_url TEXT, -- Main profile photo
ADD COLUMN IF NOT EXISTS gallery_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN artist_profiles.profile_photos IS 'Array of artist photo objects with metadata';
COMMENT ON COLUMN artist_profiles.primary_photo_url IS 'URL to primary profile photo used in trading cards';
COMMENT ON COLUMN artist_profiles.gallery_updated_at IS 'Last time photo gallery was updated';

-- Create index for querying artists with photos
CREATE INDEX IF NOT EXISTS idx_artist_profiles_has_photos
ON artist_profiles((profile_photos::text != '[]'))
WHERE profile_photos::text != '[]';

-- Ensure profile_photos is valid JSON array
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'check_profile_photos_is_array'
  ) THEN
    ALTER TABLE artist_profiles
    ADD CONSTRAINT check_profile_photos_is_array
    CHECK (jsonb_typeof(profile_photos) = 'array');
  END IF;
END $$;

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

-- Drop existing storage policies
DROP POLICY IF EXISTS "Artists can upload their own photos" ON storage.objects;
DROP POLICY IF EXISTS "Artists can update their own photos" ON storage.objects;
DROP POLICY IF EXISTS "Artists can delete their own photos" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view artist photos" ON storage.objects;

-- Create storage policies
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

-- HELPER FUNCTIONS
-- Function to get artist primary photo URL (with fallback)
CREATE OR REPLACE FUNCTION get_artist_photo_url(artist_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  photo_url TEXT;
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

  -- If still no photo, check old profile_image_url column
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

  RETURN photo_url;
END;
$$;

-- Function to set primary photo
CREATE OR REPLACE FUNCTION set_artist_primary_photo(artist_id UUID, photo_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE artist_profiles
  SET
    primary_photo_url = photo_url,
    gallery_updated_at = now()
  WHERE id = artist_id;

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

-- Function to add photo to gallery
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

  UPDATE artist_profiles
  SET
    profile_photos = profile_photos || new_photo,
    gallery_updated_at = now()
  WHERE id = artist_id;

  IF set_as_primary THEN
    PERFORM set_artist_primary_photo(artist_id, photo_url);
  END IF;

  RETURN photo_id;
END;
$$;

-- Function to remove photo
CREATE OR REPLACE FUNCTION remove_artist_photo(artist_id UUID, photo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  was_primary BOOLEAN;
BEGIN
  SELECT
    (elem->>'is_primary')::boolean
  INTO was_primary
  FROM artist_profiles,
       jsonb_array_elements(profile_photos) elem
  WHERE artist_profiles.id = artist_id
  AND elem->>'id' = photo_id::text;

  UPDATE artist_profiles
  SET
    profile_photos = (
      SELECT jsonb_agg(elem)
      FROM jsonb_array_elements(profile_photos) elem
      WHERE elem->>'id' != photo_id::text
    ),
    gallery_updated_at = now()
  WHERE id = artist_id;

  IF was_primary THEN
    UPDATE artist_profiles
    SET primary_photo_url = (profile_photos->0->>'url')::text
    WHERE id = artist_id;
  END IF;
END;
$$;

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

GRANT SELECT ON event_artists_with_photos TO authenticated, anon;

-- Backfill existing artist photos
DO $$
DECLARE
  artist RECORD;
  photo_id UUID;
BEGIN
  FOR artist IN
    SELECT id, profile_image_url
    FROM artist_profiles
    WHERE profile_image_url IS NOT NULL
    AND (profile_photos IS NULL OR profile_photos = '[]'::jsonb)
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
END $$;

-- Mark migrations as applied in history
INSERT INTO supabase_migrations.schema_migrations (version, name, statements)
VALUES
  ('20250930131500', '20250930131500_add_mediaid_role_and_trigger', ARRAY['Applied manually via Dashboard']),
  ('20250930150000', '20250930150000_add_opt_in_and_photos', ARRAY['Applied manually via Dashboard'])
ON CONFLICT (version) DO NOTHING;

-- Verification queries
SELECT '✅ Migration complete!' AS status;
SELECT 'Checking event_participants opt-in columns...' AS check;
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'event_participants' AND column_name IN ('allow_voting', 'allow_scoring', 'consent_timestamp');

SELECT 'Checking artist_profiles photo columns...' AS check;
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'artist_profiles' AND column_name IN ('profile_photos', 'primary_photo_url', 'gallery_updated_at');

SELECT 'Checking storage bucket...' AS check;
SELECT id, name, public, file_size_limit FROM storage.buckets WHERE id = 'artist-photos';