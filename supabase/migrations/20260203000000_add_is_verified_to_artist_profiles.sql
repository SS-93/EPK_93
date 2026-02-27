-- Add is_verified column to artist_profiles for E2E tests
ALTER TABLE artist_profiles
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT false;

COMMENT ON COLUMN artist_profiles.is_verified IS 'Whether artist profile has been verified by platform';
