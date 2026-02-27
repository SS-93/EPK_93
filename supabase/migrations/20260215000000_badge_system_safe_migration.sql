-- ===============================================
-- BADGE SYSTEM MIGRATION - SAFE PARALLEL APPROACH
-- ===============================================
-- This migration keeps the existing role column and adds badge system alongside
-- Allows gradual migration of dependencies before removing role column
-- ===============================================

-- ===============================================
-- STEP 1: CREATE USER_BADGES TABLE
-- ===============================================

CREATE TABLE IF NOT EXISTS user_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_type TEXT NOT NULL, -- 'fan', 'artist', 'brand', 'developer', 'admin'

  -- Badge status
  is_active BOOLEAN DEFAULT true,
  is_primary BOOLEAN DEFAULT false, -- User's primary/default badge

  -- Badge-specific metadata
  badge_metadata JSONB DEFAULT '{}', -- Store badge-specific data

  -- Verification & approval
  verification_status TEXT DEFAULT 'pending', -- 'pending', 'verified', 'rejected'
  verified_by UUID REFERENCES auth.users(id),
  verified_at TIMESTAMPTZ,

  -- Permission levels (optional - for future granular permissions)
  permissions JSONB DEFAULT '[]', -- Array of permission strings

  -- Completion tracking
  onboarding_completed BOOLEAN DEFAULT false,
  onboarding_completed_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(user_id, badge_type)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_badges_user_id ON user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_active ON user_badges(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_user_badges_primary ON user_badges(user_id, is_primary);
CREATE INDEX IF NOT EXISTS idx_user_badges_verification ON user_badges(verification_status);

-- Comment
COMMENT ON TABLE user_badges IS 'User badge system - allows users to hold multiple roles/badges simultaneously';

-- ===============================================
-- STEP 2: ADD NEW COLUMNS TO PROFILES (KEEP role FOR NOW)
-- ===============================================

-- Add new badge columns WITHOUT dropping role
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS primary_badge TEXT, -- Current active badge
  ADD COLUMN IF NOT EXISTS all_badges TEXT[] DEFAULT '{}'; -- Cached list of all active badges

-- Indexes
CREATE INDEX IF NOT EXISTS idx_profiles_primary_badge ON profiles(primary_badge);
CREATE INDEX IF NOT EXISTS idx_profiles_all_badges ON profiles USING GIN(all_badges);

-- Comments
COMMENT ON COLUMN profiles.primary_badge IS 'User primary/active badge (new system)';
COMMENT ON COLUMN profiles.all_badges IS 'Cached array of all active badges (new system)';
COMMENT ON COLUMN profiles.role IS 'DEPRECATED - Use primary_badge instead. Will be removed in future migration after dependencies are updated';

-- ===============================================
-- STEP 3: MIGRATE EXISTING DATA TO BADGE SYSTEM
-- ===============================================

-- Create badges from existing roles
INSERT INTO user_badges (user_id, badge_type, is_primary, is_active, verification_status, onboarding_completed, created_at)
SELECT
  id as user_id,
  role as badge_type,
  true as is_primary,
  true as is_active,
  'verified' as verification_status, -- Auto-verify existing roles
  onboarding_completed,
  created_at
FROM profiles
WHERE role IS NOT NULL
ON CONFLICT (user_id, badge_type) DO NOTHING;

-- Backfill primary_badge and all_badges
UPDATE profiles
SET
  primary_badge = role,
  all_badges = ARRAY[role]::text[]
WHERE role IS NOT NULL;

-- ===============================================
-- STEP 4: CREATE HELPER FUNCTIONS
-- ===============================================

-- Function to add badge to user
CREATE OR REPLACE FUNCTION add_badge_to_user(p_user_id UUID, p_badge_type TEXT)
RETURNS void AS $$
BEGIN
  -- Update profiles cache
  UPDATE profiles
  SET all_badges = array_append(all_badges, p_badge_type)
  WHERE id = p_user_id
  AND NOT (p_badge_type = ANY(all_badges));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to remove badge from user
CREATE OR REPLACE FUNCTION remove_badge_from_user(p_user_id UUID, p_badge_type TEXT)
RETURNS void AS $$
BEGIN
  -- Update profiles cache
  UPDATE profiles
  SET all_badges = array_remove(all_badges, p_badge_type)
  WHERE id = p_user_id;

  -- If removing primary badge, set new primary
  UPDATE profiles
  SET primary_badge = all_badges[1]
  WHERE id = p_user_id
  AND primary_badge = p_badge_type
  AND array_length(all_badges, 1) > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to set primary badge
CREATE OR REPLACE FUNCTION set_primary_badge(p_user_id UUID, p_badge_type TEXT)
RETURNS void AS $$
BEGIN
  -- Verify user has this badge
  IF NOT EXISTS (
    SELECT 1 FROM user_badges
    WHERE user_id = p_user_id
    AND badge_type = p_badge_type
    AND is_active = true
    AND verification_status = 'verified'
  ) THEN
    RAISE EXCEPTION 'User does not have active verified badge: %', p_badge_type;
  END IF;

  -- Remove primary from all badges
  UPDATE user_badges
  SET is_primary = false
  WHERE user_id = p_user_id;

  -- Set new primary
  UPDATE user_badges
  SET is_primary = true
  WHERE user_id = p_user_id AND badge_type = p_badge_type;

  -- Update profiles cache
  UPDATE profiles
  SET primary_badge = p_badge_type
  WHERE id = p_user_id;

  -- Also update role column for backward compatibility
  UPDATE profiles
  SET role = p_badge_type::user_role
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has badge
CREATE OR REPLACE FUNCTION user_has_badge(p_user_id UUID, p_badge_type TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_badges
    WHERE user_id = p_user_id
    AND badge_type = p_badge_type
    AND is_active = true
    AND verification_status = 'verified'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===============================================
-- STEP 5: UPDATE handle_new_user TRIGGER TO CREATE BADGES
-- ===============================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  user_role TEXT;
BEGIN
  -- Determine role from metadata or default to 'fan'
  user_role := COALESCE(NEW.raw_user_meta_data->>'role', 'fan');

  -- Create profile (keeping role for backward compatibility)
  INSERT INTO public.profiles (id, display_name, role, primary_badge, all_badges, email_verified, onboarding_completed)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    user_role::user_role, -- Keep role for backward compatibility
    user_role, -- Set primary_badge
    ARRAY[user_role], -- Set all_badges
    NEW.email_confirmed_at IS NOT NULL,
    false
  )
  ON CONFLICT (id) DO NOTHING;

  -- Create badge (new system)
  INSERT INTO public.user_badges (user_id, badge_type, is_primary, is_active, verification_status, onboarding_completed)
  VALUES (
    NEW.id,
    user_role,
    true, -- First badge is primary
    true,
    'verified', -- Auto-verify fan/developer badges
    false
  )
  ON CONFLICT (user_id, badge_type) DO NOTHING;

  -- Create MediaID with role field
  INSERT INTO public.media_ids (user_uuid, role, interests, genre_preferences, privacy_settings, version, is_active)
  VALUES (
    NEW.id,
    user_role::user_role,
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
  ON CONFLICT (user_uuid, role) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail signup
    RAISE WARNING 'Error in handle_new_user for %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ===============================================
-- STEP 6: CREATE BADGE SYNC TRIGGER (Keep role and badges in sync)
-- ===============================================

-- Trigger to sync badges when profile role changes
CREATE OR REPLACE FUNCTION sync_role_to_badges()
RETURNS trigger AS $$
BEGIN
  -- If role changed, update primary badge
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    -- Update primary badge
    NEW.primary_badge := NEW.role::text;

    -- Ensure badge exists
    INSERT INTO user_badges (user_id, badge_type, is_primary, is_active, verification_status)
    VALUES (NEW.id, NEW.role::text, true, true, 'verified')
    ON CONFLICT (user_id, badge_type) DO UPDATE
    SET is_primary = true;

    -- Update all_badges cache
    NEW.all_badges := ARRAY(
      SELECT badge_type FROM user_badges
      WHERE user_id = NEW.id
      AND is_active = true
      ORDER BY is_primary DESC, created_at
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_role_to_badges_trigger
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_role_to_badges();

-- ===============================================
-- STEP 7: CREATE RLS POLICIES FOR USER_BADGES
-- ===============================================

-- Enable RLS
ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;

-- Users can view their own badges
CREATE POLICY "Users can view own badges"
  ON user_badges FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Public can view verified active badges (for profile display)
CREATE POLICY "Public can view verified badges"
  ON user_badges FOR SELECT
  TO public
  USING (is_active = true AND verification_status = 'verified');

-- Users can request new badges
CREATE POLICY "Users can request badges"
  ON user_badges FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Admins can manage all badges
CREATE POLICY "Admins can manage badges"
  ON user_badges FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND (role = 'admin' OR primary_badge = 'admin')
    )
  );

-- ===============================================
-- STEP 8: CREATE BADGE MANAGEMENT VIEWS
-- ===============================================

-- View for active user badges with profile info
CREATE OR REPLACE VIEW user_badges_view AS
SELECT
  ub.*,
  p.display_name,
  p.avatar_url,
  p.email_verified
FROM user_badges ub
JOIN profiles p ON ub.user_id = p.id
WHERE ub.is_active = true;

GRANT SELECT ON user_badges_view TO authenticated, anon;

-- View for pending badge requests (admin use)
CREATE OR REPLACE VIEW pending_badge_requests AS
SELECT
  ub.*,
  p.display_name,
  p.avatar_url,
  u.email
FROM user_badges ub
JOIN profiles p ON ub.user_id = p.id
JOIN auth.users u ON ub.user_id = u.id
WHERE ub.verification_status = 'pending'
ORDER BY ub.created_at DESC;

GRANT SELECT ON pending_badge_requests TO authenticated;

-- ===============================================
-- STEP 9: GRANT PERMISSIONS
-- ===============================================

GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON public.user_badges TO authenticated;
GRANT SELECT ON public.user_badges TO anon;

-- ===============================================
-- STEP 10: VERIFICATION
-- ===============================================

-- Verify migration
DO $$
DECLARE
  badge_count INTEGER;
  profile_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO badge_count FROM user_badges;
  SELECT COUNT(*) INTO profile_count FROM profiles WHERE role IS NOT NULL;

  RAISE NOTICE '✅ Badge migration complete!';
  RAISE NOTICE '📊 Created % badges from % profiles', badge_count, profile_count;
  RAISE NOTICE '⚠️  Note: role column still exists for backward compatibility';
  RAISE NOTICE '📝 Next: Update dependent policies/triggers to use badges, then drop role column';
END $$;

-- List objects still depending on role column
SELECT
  'Reminder: These objects still depend on profiles.role column:' as notice;

SELECT
  conname as constraint_or_trigger_name,
  contype as type
FROM pg_constraint
WHERE conrelid = 'profiles'::regclass
AND conkey::text LIKE '%role%';
