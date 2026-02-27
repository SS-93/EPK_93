-- ===============================================
-- BADGE SYSTEM: UPDATE DEPENDENCIES
-- ===============================================
-- Run this AFTER 20260215000000_badge_system_safe_migration.sql
-- This updates common policies/views to use badges instead of role
-- ===============================================

BEGIN;

-- ===============================================
-- STEP 1: UPDATE STORAGE POLICIES
-- ===============================================

-- Artists can upload content including video
DROP POLICY IF EXISTS "Artists can upload content including video" ON storage.objects;
CREATE POLICY "Artists can upload content including video"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id IN ('audio-files', 'video-files', 'user-content') AND
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- Artists can upload their own content
DROP POLICY IF EXISTS "Artists can upload their own content" ON storage.objects;
CREATE POLICY "Artists can upload their own content"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id IN ('user-content', 'audio-files', 'video-files') AND
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- Brands can upload their own assets
DROP POLICY IF EXISTS "Brands can upload their own assets" ON storage.objects;
CREATE POLICY "Brands can upload their own assets"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id IN ('brand-assets', 'user-content') AND
  'brand' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

RAISE NOTICE '✅ Storage policies updated';

-- ===============================================
-- STEP 2: UPDATE TABLE POLICIES
-- ===============================================

-- Public can view artist profiles
DROP POLICY IF EXISTS "Public can view artist profiles" ON profiles;
CREATE POLICY "Public can view artist profiles"
ON profiles FOR SELECT
TO public
USING ('artist' = ANY(all_badges));

-- Artists can view brand profiles
DROP POLICY IF EXISTS "Artists can view brand profiles" ON brands;
CREATE POLICY "Artists can view brand profiles"
ON brands FOR SELECT
TO authenticated
USING (
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- Artists can view relevant campaigns
DROP POLICY IF EXISTS "Artists can view relevant campaigns" ON campaigns;
CREATE POLICY "Artists can view relevant campaigns"
ON campaigns FOR SELECT
TO authenticated
USING (
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

RAISE NOTICE '✅ Table policies updated';

-- ===============================================
-- STEP 3: UPDATE COLISEUM POLICIES
-- ===============================================

-- Coliseum metrics admin
DROP POLICY IF EXISTS "coliseum_metrics_write_admin" ON coliseum_metrics;
CREATE POLICY "coliseum_metrics_write_admin"
ON coliseum_metrics FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- Coliseum rollups admin
DROP POLICY IF EXISTS "coliseum_rollups_write_admin" ON coliseum_rollups;
CREATE POLICY "coliseum_rollups_write_admin"
ON coliseum_rollups FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- Coliseum leaderboards admin
DROP POLICY IF EXISTS "coliseum_leaderboards_write_admin" ON coliseum_leaderboards;
CREATE POLICY "coliseum_leaderboards_write_admin"
ON coliseum_leaderboards FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- Coliseum reports admin
DROP POLICY IF EXISTS "coliseum_reports_admin" ON coliseum_reports;
CREATE POLICY "coliseum_reports_admin"
ON coliseum_reports FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

RAISE NOTICE '✅ Coliseum policies updated';

-- ===============================================
-- STEP 4: UPDATE COLISEUM VIEWS
-- ===============================================

-- Coliseum metrics view admin
DROP VIEW IF EXISTS coliseum_metrics_view_admin;
CREATE OR REPLACE VIEW coliseum_metrics_view_admin AS
SELECT *
FROM coliseum_metrics
WHERE EXISTS (
  SELECT 1 FROM profiles
  WHERE id = auth.uid()
  AND (primary_badge = 'admin' OR 'admin' = ANY(all_badges))
);

GRANT SELECT ON coliseum_metrics_view_admin TO authenticated;

RAISE NOTICE '✅ Coliseum views updated';

-- ===============================================
-- STEP 5: VERIFY NO REMAINING DEPENDENCIES
-- ===============================================

-- Check for remaining dependencies
DO $$
DECLARE
  policy_count INTEGER;
  function_count INTEGER;
  view_count INTEGER;
BEGIN
  -- Check policies
  SELECT COUNT(*) INTO policy_count
  FROM pg_policies
  WHERE (
    pg_get_expr(qual, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%'
    OR pg_get_expr(with_check, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%'
  );

  -- Check functions
  SELECT COUNT(*) INTO function_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE pg_get_functiondef(p.oid) ILIKE '%profiles.role%'
  AND n.nspname = 'public'
  AND p.proname NOT IN ('handle_new_user', 'sync_role_to_badges'); -- Exclude migration functions

  -- Check views
  SELECT COUNT(*) INTO view_count
  FROM pg_views
  WHERE definition ILIKE '%profiles.role%'
  AND schemaname = 'public'
  AND viewname NOT LIKE '%_view_admin'; -- We just updated these

  IF policy_count > 0 OR function_count > 0 OR view_count > 0 THEN
    RAISE WARNING 'Dependencies still exist: % policies, % functions, % views', policy_count, function_count, view_count;
    RAISE WARNING 'Review BADGE_MIGRATION_DEPENDENCY_UPDATE_GUIDE.md for manual updates';
  ELSE
    RAISE NOTICE '✅ All common dependencies updated!';
    RAISE NOTICE '📝 Next: Test badge system, then run 20260215030000_badge_system_cleanup.sql';
  END IF;
END $$;

COMMIT;

-- ===============================================
-- FINAL NOTES
-- ===============================================

SELECT '✅ Dependency update complete!' as status;
SELECT '📝 Next steps:' as next_steps;
SELECT '1. Test badge system in frontend' as step_1;
SELECT '2. Verify policies work correctly' as step_2;
SELECT '3. Check for any remaining dependencies' as step_3;
SELECT '4. Run final cleanup migration to drop role column' as step_4;
