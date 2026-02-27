-- ===============================================
-- BADGE SYSTEM: FINAL CLEANUP
-- ===============================================
-- ⚠️ WARNING: Run this ONLY after:
--   1. 20260215000000_badge_system_safe_migration.sql
--   2. 20260215020000_badge_system_update_dependencies.sql
--   3. All dependencies verified and updated
--   4. Badge system tested in production
-- This migration DROPS the role column (irreversible!)
-- ===============================================

BEGIN;

-- ===============================================
-- STEP 1: SAFETY CHECK - VERIFY NO DEPENDENCIES
-- ===============================================

DO $$
DECLARE
  dep_count INTEGER;
  policy_count INTEGER;
  function_count INTEGER;
  view_count INTEGER;
  error_message TEXT := '';
BEGIN
  RAISE NOTICE '🔍 Checking for remaining dependencies on profiles.role...';

  -- Check system dependencies
  SELECT COUNT(*) INTO dep_count
  FROM pg_depend d
  WHERE d.refobjid = (
    SELECT oid FROM pg_class WHERE relname = 'profiles'
  )
  AND d.refobjsubid = (
    SELECT attnum FROM pg_attribute
    WHERE attrelid = 'profiles'::regclass AND attname = 'role'
  );

  -- Check policies
  SELECT COUNT(*) INTO policy_count
  FROM pg_policies
  WHERE (
    pg_get_expr(qual, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%'
    OR pg_get_expr(with_check, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%'
  );

  -- Check functions (excluding migration functions)
  SELECT COUNT(*) INTO function_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE pg_get_functiondef(p.oid) ILIKE '%profiles.role%'
  AND n.nspname = 'public'
  AND p.proname NOT IN ('handle_new_user', 'sync_role_to_badges');

  -- Check views
  SELECT COUNT(*) INTO view_count
  FROM pg_views
  WHERE definition ILIKE '%profiles.role%'
  AND schemaname = 'public';

  -- Build error message if dependencies exist
  IF dep_count > 0 THEN
    error_message := error_message || format('System dependencies: %s | ', dep_count);
  END IF;
  IF policy_count > 0 THEN
    error_message := error_message || format('Policies: %s | ', policy_count);
  END IF;
  IF function_count > 0 THEN
    error_message := error_message || format('Functions: %s | ', function_count);
  END IF;
  IF view_count > 0 THEN
    error_message := error_message || format('Views: %s | ', view_count);
  END IF;

  -- Abort if dependencies exist
  IF error_message != '' THEN
    RAISE EXCEPTION 'Cannot drop role column. Dependencies still exist: %', error_message
      USING HINT = 'Update all dependent objects first. See BADGE_MIGRATION_DEPENDENCY_UPDATE_GUIDE.md';
  END IF;

  RAISE NOTICE '✅ No dependencies found. Safe to proceed.';
END $$;

-- ===============================================
-- STEP 2: BACKUP DATA (Just in Case)
-- ===============================================

-- Create temporary backup of role data
CREATE TEMP TABLE profiles_role_backup AS
SELECT id, role::text as role_backup, primary_badge, all_badges
FROM profiles
WHERE role IS NOT NULL;

RAISE NOTICE '📦 Backed up % role records to temp table', (SELECT COUNT(*) FROM profiles_role_backup);

-- ===============================================
-- STEP 3: DROP SYNC TRIGGER
-- ===============================================

-- Drop the trigger that syncs role <-> badges
DROP TRIGGER IF EXISTS sync_role_to_badges_trigger ON profiles;
DROP FUNCTION IF EXISTS sync_role_to_badges();

RAISE NOTICE '✅ Sync trigger removed';

-- ===============================================
-- STEP 4: DROP ROLE COLUMN
-- ===============================================

-- This is the point of no return
ALTER TABLE profiles DROP COLUMN IF EXISTS role;

RAISE NOTICE '✅ role column dropped from profiles table';

-- ===============================================
-- STEP 5: UPDATE COMMENTS & DOCUMENTATION
-- ===============================================

COMMENT ON TABLE profiles IS 'User profiles with badge-based role system. Use primary_badge and all_badges for role checking.';
COMMENT ON COLUMN profiles.primary_badge IS 'User primary/active badge (replaces deprecated role column)';
COMMENT ON COLUMN profiles.all_badges IS 'Cached array of all active badges (fast lookup for RLS policies)';

-- ===============================================
-- STEP 6: VERIFY BADGE SYSTEM INTEGRITY
-- ===============================================

DO $$
DECLARE
  orphaned_profiles INTEGER;
  users_without_badges INTEGER;
  badges_without_profiles INTEGER;
BEGIN
  -- Check for profiles without badges
  SELECT COUNT(*) INTO users_without_badges
  FROM profiles p
  WHERE NOT EXISTS (
    SELECT 1 FROM user_badges ub
    WHERE ub.user_id = p.id
    AND ub.is_active = true
  );

  -- Check for badges without profiles
  SELECT COUNT(*) INTO badges_without_profiles
  FROM user_badges ub
  WHERE NOT EXISTS (
    SELECT 1 FROM profiles p WHERE p.id = ub.user_id
  );

  -- Check for mismatched primary_badge
  SELECT COUNT(*) INTO orphaned_profiles
  FROM profiles p
  WHERE p.primary_badge IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM user_badges ub
    WHERE ub.user_id = p.id
    AND ub.badge_type = p.primary_badge
    AND ub.is_active = true
    AND ub.is_primary = true
  );

  IF users_without_badges > 0 THEN
    RAISE WARNING '⚠️  Found % users without badges', users_without_badges;
  END IF;

  IF badges_without_profiles > 0 THEN
    RAISE WARNING '⚠️  Found % badges without profiles', badges_without_profiles;
  END IF;

  IF orphaned_profiles > 0 THEN
    RAISE WARNING '⚠️  Found % profiles with mismatched primary_badge', orphaned_profiles;
  END IF;

  IF users_without_badges = 0 AND badges_without_profiles = 0 AND orphaned_profiles = 0 THEN
    RAISE NOTICE '✅ Badge system integrity verified';
  ELSE
    RAISE WARNING 'Badge system has integrity issues. Run repair queries.';
  END IF;
END $$;

-- ===============================================
-- STEP 7: REPAIR QUERIES (IF NEEDED)
-- ===============================================

-- Auto-fix users without badges (create fan badge)
INSERT INTO user_badges (user_id, badge_type, is_primary, is_active, verification_status)
SELECT
  p.id,
  'fan' as badge_type,
  true as is_primary,
  true as is_active,
  'verified' as verification_status
FROM profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM user_badges ub
  WHERE ub.user_id = p.id
  AND ub.is_active = true
)
ON CONFLICT (user_id, badge_type) DO NOTHING;

-- Auto-fix mismatched primary_badge
UPDATE profiles p
SET primary_badge = (
  SELECT badge_type FROM user_badges
  WHERE user_id = p.id
  AND is_primary = true
  AND is_active = true
  LIMIT 1
)
WHERE p.primary_badge IS NULL
OR NOT EXISTS (
  SELECT 1 FROM user_badges ub
  WHERE ub.user_id = p.id
  AND ub.badge_type = p.primary_badge
  AND ub.is_primary = true
  AND ub.is_active = true
);

-- Auto-fix all_badges cache
UPDATE profiles p
SET all_badges = (
  SELECT ARRAY_AGG(badge_type ORDER BY is_primary DESC, created_at)
  FROM user_badges
  WHERE user_id = p.id
  AND is_active = true
);

RAISE NOTICE '✅ Badge system repairs applied';

-- ===============================================
-- STEP 8: UPDATE media_ids STRATEGY
-- ===============================================

-- Add role_preferences column if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'media_ids' AND column_name = 'role_preferences'
  ) THEN
    ALTER TABLE media_ids
      ADD COLUMN role_preferences JSONB DEFAULT '{}';

    RAISE NOTICE '✅ Added role_preferences to media_ids';
  ELSE
    RAISE NOTICE 'ℹ️  role_preferences already exists in media_ids';
  END IF;
END $$;

-- Migrate existing MediaID data to role_preferences structure
-- This allows one MediaID per user with preferences per badge
UPDATE media_ids
SET role_preferences = jsonb_build_object(
  role::text,
  jsonb_build_object(
    'interests', interests,
    'genre_preferences', genre_preferences
  )
)
WHERE role_preferences = '{}'::jsonb
AND role IS NOT NULL;

COMMENT ON COLUMN media_ids.role_preferences IS 'JSONB object mapping badge_type -> preferences. Allows one MediaID per user with per-badge preferences.';

-- ===============================================
-- STEP 9: FINAL VERIFICATION
-- ===============================================

DO $$
DECLARE
  profile_count INTEGER;
  badge_count INTEGER;
  user_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO profile_count FROM profiles;
  SELECT COUNT(DISTINCT user_id) INTO user_count FROM user_badges WHERE is_active = true;
  SELECT COUNT(*) INTO badge_count FROM user_badges WHERE is_active = true;

  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════';
  RAISE NOTICE '✅ BADGE SYSTEM MIGRATION COMPLETE!';
  RAISE NOTICE '════════════════════════════════════════';
  RAISE NOTICE 'Total profiles: %', profile_count;
  RAISE NOTICE 'Users with badges: %', user_count;
  RAISE NOTICE 'Total active badges: %', badge_count;
  RAISE NOTICE 'Average badges per user: %', ROUND(badge_count::numeric / NULLIF(user_count, 0), 2);
  RAISE NOTICE '';
  RAISE NOTICE '📝 Next steps:';
  RAISE NOTICE '1. Update frontend to use badge system (useBadges hook)';
  RAISE NOTICE '2. Update backend routes to check badges instead of role';
  RAISE NOTICE '3. Deploy badge management UI';
  RAISE NOTICE '4. Test badge switching and dashboard access';
  RAISE NOTICE '5. Document badge request/approval process';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️  Important: The role column has been removed!';
  RAISE NOTICE '    All code must now use primary_badge or all_badges';
  RAISE NOTICE '════════════════════════════════════════';
END $$;

COMMIT;

-- ===============================================
-- ROLLBACK INSTRUCTIONS (Emergency Only)
-- ===============================================

/*
IF YOU NEED TO ROLLBACK (DO NOT RUN UNLESS EMERGENCY):

BEGIN;

-- Re-add role column
ALTER TABLE profiles ADD COLUMN role user_role;

-- Populate from primary_badge
UPDATE profiles
SET role = primary_badge::user_role
WHERE primary_badge IN ('fan', 'artist', 'brand', 'developer', 'admin');

-- Recreate sync trigger
CREATE OR REPLACE FUNCTION sync_role_to_badges()
RETURNS trigger AS $func$
BEGIN
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    NEW.primary_badge := NEW.role::text;
    INSERT INTO user_badges (user_id, badge_type, is_primary, is_active, verification_status)
    VALUES (NEW.id, NEW.role::text, true, true, 'verified')
    ON CONFLICT (user_id, badge_type) DO UPDATE SET is_primary = true;
    NEW.all_badges := ARRAY(
      SELECT badge_type FROM user_badges
      WHERE user_id = NEW.id AND is_active = true
      ORDER BY is_primary DESC, created_at
    );
  END IF;
  RETURN NEW;
END;
$func$ LANGUAGE plpgsql;

CREATE TRIGGER sync_role_to_badges_trigger
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION sync_role_to_badges();

COMMIT;

NOTE: This rollback does NOT restore old policies/views. Those must be manually recreated.
*/
