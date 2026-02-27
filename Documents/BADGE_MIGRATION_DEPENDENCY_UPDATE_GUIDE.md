# Badge Migration: Dependency Update Guide

**Date:** February 15, 2026
**Status:** Step-by-step dependency migration
**Priority:** Run after badge_system_safe_migration.sql

---

## 🎯 Overview

The safe migration created the badge system **alongside** the existing role column. Now we need to update all dependent objects (triggers, policies, views) to use the new badge system instead of `profiles.role`.

**Dependencies to Update:**
1. ✅ `auto_create_artist_profile` trigger - **UPDATED in safe migration**
2. ❌ Storage policy: "Artists can upload content including video"
3. ❌ Table policy: "Public can view artist profiles" (profiles table)
4. ❌ Table policy: "Artists can view brand profiles" (brands table)
5. ❌ Table policy: "Artists can view relevant campaigns" (campaigns table)
6. ❌ Storage policy: "Artists can upload their own content"
7. ❌ Storage policy: "Brands can upload their own assets"
8. ❌ View: `coliseum_metrics_view_admin`
9. ❌ Policy: `coliseum_metrics_write_admin`
10. ❌ Policy: `coliseum_rollups_write_admin`
11. ❌ Policy: `coliseum_leaderboards_write_admin`
12. ❌ Policy: `coliseum_reports_admin`

---

## 📋 Pre-Migration Checklist

Before updating dependencies:
- [x] Run `20260215000000_badge_system_safe_migration.sql`
- [ ] Verify badge system works (test badge switching in frontend)
- [ ] Backup database
- [ ] Test in staging environment first
- [ ] Plan maintenance window (5-10 minutes)

---

## 🔧 Step-by-Step Updates

### **Step 1: Update Storage Policies**

#### **1.1: Artists can upload content including video**

**Old Policy (uses role):**
```sql
-- Check what the current policy looks like
SELECT * FROM pg_policies WHERE policyname LIKE '%Artists can upload content%';
```

**New Policy (uses badges):**
```sql
-- Drop old policy
DROP POLICY IF EXISTS "Artists can upload content including video" ON storage.objects;

-- Create new policy using badges
CREATE POLICY "Artists can upload content including video"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id IN ('audio-files', 'video-files') AND
  (
    -- Check if user has artist badge
    EXISTS (
      SELECT 1 FROM user_badges
      WHERE user_id = auth.uid()
      AND badge_type = 'artist'
      AND is_active = true
      AND verification_status = 'verified'
    )
    OR
    -- Alternative: Check primary_badge or all_badges cache
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
      AND (primary_badge = 'artist' OR 'artist' = ANY(all_badges))
    )
  )
);
```

**Recommended:** Use the `all_badges` cache approach (faster, no join to user_badges):
```sql
DROP POLICY IF EXISTS "Artists can upload content including video" ON storage.objects;

CREATE POLICY "Artists can upload content including video"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id IN ('audio-files', 'video-files') AND
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);
```

---

#### **1.2: Artists can upload their own content**

```sql
DROP POLICY IF EXISTS "Artists can upload their own content" ON storage.objects;

CREATE POLICY "Artists can upload their own content"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'user-content' AND
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);
```

---

#### **1.3: Brands can upload their own assets**

```sql
DROP POLICY IF EXISTS "Brands can upload their own assets" ON storage.objects;

CREATE POLICY "Brands can upload their own assets"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'brand-assets' AND
  'brand' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);
```

---

### **Step 2: Update Table Policies**

#### **2.1: Public can view artist profiles (profiles table)**

**Find current policy:**
```sql
SELECT * FROM pg_policies
WHERE schemaname = 'public'
AND tablename = 'profiles'
AND policyname = 'Public can view artist profiles';
```

**Update policy:**
```sql
DROP POLICY IF EXISTS "Public can view artist profiles" ON profiles;

CREATE POLICY "Public can view artist profiles"
ON profiles FOR SELECT
TO public
USING ('artist' = ANY(all_badges));
```

---

#### **2.2: Artists can view brand profiles (brands table)**

```sql
DROP POLICY IF EXISTS "Artists can view brand profiles" ON brands;

CREATE POLICY "Artists can view brand profiles"
ON brands FOR SELECT
TO authenticated
USING (
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);
```

---

#### **2.3: Artists can view relevant campaigns (campaigns table)**

```sql
DROP POLICY IF EXISTS "Artists can view relevant campaigns" ON campaigns;

CREATE POLICY "Artists can view relevant campaigns"
ON campaigns FOR SELECT
TO authenticated
USING (
  'artist' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);
```

---

### **Step 3: Update Coliseum Views & Policies**

#### **3.1: Update coliseum_metrics_view_admin view**

**Find current view:**
```sql
SELECT pg_get_viewdef('coliseum_metrics_view_admin', true);
```

**Likely uses:**
```sql
-- Old view definition (example)
CREATE OR REPLACE VIEW coliseum_metrics_view_admin AS
SELECT *
FROM coliseum_metrics
WHERE EXISTS (
  SELECT 1 FROM profiles
  WHERE id = auth.uid() AND role = 'admin'
);
```

**Update to use badges:**
```sql
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
```

---

#### **3.2: Update Coliseum Admin Policies**

**For each coliseum table with admin policies:**

```sql
-- coliseum_metrics
DROP POLICY IF EXISTS "coliseum_metrics_write_admin" ON coliseum_metrics;

CREATE POLICY "coliseum_metrics_write_admin"
ON coliseum_metrics FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- coliseum_rollups
DROP POLICY IF EXISTS "coliseum_rollups_write_admin" ON coliseum_rollups;

CREATE POLICY "coliseum_rollups_write_admin"
ON coliseum_rollups FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- coliseum_leaderboards
DROP POLICY IF EXISTS "coliseum_leaderboards_write_admin" ON coliseum_leaderboards;

CREATE POLICY "coliseum_leaderboards_write_admin"
ON coliseum_leaderboards FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);

-- coliseum_reports
DROP POLICY IF EXISTS "coliseum_reports_admin" ON coliseum_reports;

CREATE POLICY "coliseum_reports_admin"
ON coliseum_reports FOR ALL
TO authenticated
USING (
  'admin' = ANY(
    SELECT all_badges FROM profiles WHERE id = auth.uid()
  )
);
```

---

### **Step 4: Update Any Custom Functions**

Check if any custom functions reference `profiles.role`:

```sql
-- Find functions that might use role
SELECT
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_functiondef(p.oid) as function_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE pg_get_functiondef(p.oid) ILIKE '%profiles.role%'
AND n.nspname = 'public';
```

For each function found, review and update to use `primary_badge` or `all_badges`.

---

### **Step 5: Verify All Dependencies Updated**

Run this query to check if any policies/triggers still reference `profiles.role`:

```sql
-- Check for remaining dependencies
SELECT
  'Policy: ' || schemaname || '.' || tablename || ' -> ' || policyname as object,
  pg_get_expr(qual, (schemaname||'.'||tablename)::regclass) as condition
FROM pg_policies
WHERE pg_get_expr(qual, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%'
OR pg_get_expr(with_check, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%';

-- Check functions
SELECT
  'Function: ' || n.nspname || '.' || p.proname as object
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE pg_get_functiondef(p.oid) ILIKE '%profiles.role%'
AND n.nspname = 'public';

-- Check views
SELECT
  'View: ' || schemaname || '.' || viewname as object
FROM pg_views
WHERE definition ILIKE '%profiles.role%'
AND schemaname = 'public';
```

**Expected Result:** No rows returned (all dependencies updated)

---

### **Step 6: Test Badge System**

Before dropping the `role` column, verify badge system works:

#### **Frontend Tests:**
1. ✅ User can switch badges via badge selector
2. ✅ Dashboard access works with badge-based routing
3. ✅ Smart route guard allows/denies access correctly
4. ✅ Badge request flow works
5. ✅ Admin can approve badge requests

#### **Backend Tests:**
```sql
-- Test 1: Check user has correct badges
SELECT user_id, badge_type, is_primary, verification_status
FROM user_badges
WHERE user_id = 'YOUR_TEST_USER_ID';

-- Test 2: Verify primary_badge matches
SELECT id, primary_badge, all_badges, role
FROM profiles
WHERE id = 'YOUR_TEST_USER_ID';

-- Test 3: Test policy access
SET ROLE authenticated;
SET request.jwt.claims.sub TO 'YOUR_TEST_USER_ID';

-- Try accessing artist-only content (should work if user has artist badge)
SELECT * FROM artist_profiles LIMIT 1;

RESET ROLE;
```

---

### **Step 7: Final Cleanup - Drop role Column**

**⚠️ WARNING: Only run this after ALL dependencies are updated and tested!**

Create final migration:

```sql
-- ===============================================
-- FINAL CLEANUP: DROP ROLE COLUMN
-- ===============================================
-- Run ONLY after all dependencies updated and tested
-- This is a one-way migration - cannot be easily reversed
-- ===============================================

-- Step 1: Verify no dependencies remain
DO $$
DECLARE
  dep_count INTEGER;
BEGIN
  -- Check for any remaining dependencies
  SELECT COUNT(*) INTO dep_count
  FROM pg_depend d
  JOIN pg_attribute a ON a.attrelid = d.refclassid AND a.attnum = d.refobjsubid
  WHERE a.attname = 'role'
  AND a.attrelid = 'profiles'::regclass;

  IF dep_count > 0 THEN
    RAISE EXCEPTION 'Cannot drop role column: % dependencies still exist. Update all dependent objects first.', dep_count;
  END IF;

  RAISE NOTICE '✅ No dependencies found. Safe to drop role column.';
END $$;

-- Step 2: Drop the role column
ALTER TABLE profiles DROP COLUMN role;

-- Step 3: Drop sync trigger (no longer needed)
DROP TRIGGER IF EXISTS sync_role_to_badges_trigger ON profiles;
DROP FUNCTION IF EXISTS sync_role_to_badges();

-- Step 4: Update comments
COMMENT ON COLUMN profiles.primary_badge IS 'User primary/active badge';
COMMENT ON COLUMN profiles.all_badges IS 'Cached array of all active badges';

-- Step 5: Verification
SELECT 'Migration complete! role column removed.' as status;
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'profiles'
AND column_name IN ('primary_badge', 'all_badges');
```

---

## 📊 Migration Checklist

### **Pre-Migration:**
- [ ] Run safe migration (creates badge system alongside role)
- [ ] Verify badges created for all users
- [ ] Test badge switching in frontend
- [ ] Backup database

### **Dependency Updates:**
- [ ] Update storage policies (3 policies)
- [ ] Update table policies (3 policies)
- [ ] Update Coliseum views (1 view)
- [ ] Update Coliseum policies (4 policies)
- [ ] Update custom functions (if any)
- [ ] Verify no dependencies remain

### **Testing:**
- [ ] Test badge switching
- [ ] Test dashboard access control
- [ ] Test file upload permissions
- [ ] Test admin badge approval
- [ ] Verify RLS policies work correctly

### **Cleanup:**
- [ ] Run final cleanup migration
- [ ] Drop role column
- [ ] Update documentation
- [ ] Update frontend code to remove role references

---

## 🚨 Rollback Plan

If issues arise after updating dependencies:

### **Rollback Step 1: Restore role column (if dropped)**
```sql
-- Re-add role column
ALTER TABLE profiles ADD COLUMN role user_role;

-- Repopulate from primary_badge
UPDATE profiles
SET role = primary_badge::user_role
WHERE primary_badge IS NOT NULL;
```

### **Rollback Step 2: Restore old policies**
- Keep backups of old policy definitions
- Use `CREATE OR REPLACE POLICY` to restore

### **Rollback Step 3: Disable badge system temporarily**
```sql
-- Mark all badges as inactive
UPDATE user_badges SET is_active = false;

-- Revert to role-based routing in frontend
```

---

## 📝 Automated Migration Script

For convenience, here's a complete script that updates all common dependencies:

```sql
-- Run this AFTER the safe migration and BEFORE dropping role column
-- This updates the most common dependencies

BEGIN;

-- 1. Storage policies
DROP POLICY IF EXISTS "Artists can upload content including video" ON storage.objects;
CREATE POLICY "Artists can upload content including video"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id IN ('audio-files', 'video-files') AND
  'artist' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid())
);

DROP POLICY IF EXISTS "Artists can upload their own content" ON storage.objects;
CREATE POLICY "Artists can upload their own content"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'user-content' AND
  'artist' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid())
);

DROP POLICY IF EXISTS "Brands can upload their own assets" ON storage.objects;
CREATE POLICY "Brands can upload their own assets"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'brand-assets' AND
  'brand' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid())
);

-- 2. Table policies
DROP POLICY IF EXISTS "Public can view artist profiles" ON profiles;
CREATE POLICY "Public can view artist profiles"
ON profiles FOR SELECT TO public
USING ('artist' = ANY(all_badges));

DROP POLICY IF EXISTS "Artists can view brand profiles" ON brands;
CREATE POLICY "Artists can view brand profiles"
ON brands FOR SELECT TO authenticated
USING ('artist' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "Artists can view relevant campaigns" ON campaigns;
CREATE POLICY "Artists can view relevant campaigns"
ON campaigns FOR SELECT TO authenticated
USING ('artist' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid()));

-- 3. Coliseum admin policies
DROP POLICY IF EXISTS "coliseum_metrics_write_admin" ON coliseum_metrics;
CREATE POLICY "coliseum_metrics_write_admin"
ON coliseum_metrics FOR ALL TO authenticated
USING ('admin' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "coliseum_rollups_write_admin" ON coliseum_rollups;
CREATE POLICY "coliseum_rollups_write_admin"
ON coliseum_rollups FOR ALL TO authenticated
USING ('admin' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "coliseum_leaderboards_write_admin" ON coliseum_leaderboards;
CREATE POLICY "coliseum_leaderboards_write_admin"
ON coliseum_leaderboards FOR ALL TO authenticated
USING ('admin' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid()));

DROP POLICY IF EXISTS "coliseum_reports_admin" ON coliseum_reports;
CREATE POLICY "coliseum_reports_admin"
ON coliseum_reports FOR ALL TO authenticated
USING ('admin' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid()));

-- 4. Views (example for coliseum_metrics_view_admin)
DROP VIEW IF EXISTS coliseum_metrics_view_admin;
CREATE OR REPLACE VIEW coliseum_metrics_view_admin AS
SELECT * FROM coliseum_metrics
WHERE EXISTS (
  SELECT 1 FROM profiles
  WHERE id = auth.uid()
  AND (primary_badge = 'admin' OR 'admin' = ANY(all_badges))
);
GRANT SELECT ON coliseum_metrics_view_admin TO authenticated;

COMMIT;

-- Verify
SELECT 'Dependencies updated successfully!' as status;
```

---

## ✅ Success Criteria

**Badge system is fully migrated when:**
- [ ] All users have badges matching their roles
- [ ] Badge switching works without errors
- [ ] All RLS policies use badges instead of role
- [ ] No objects depend on profiles.role column
- [ ] role column successfully dropped
- [ ] Frontend uses badge system exclusively
- [ ] No errors in production logs

---

## 📞 Support

If you encounter issues:
1. Check error logs for specific policy/trigger names
2. Use the verification queries to identify remaining dependencies
3. Review the rollback plan if needed
4. Test each update in staging first

---

**Document Status:** ✅ Complete
**Ready for:** Step-by-step execution
**Estimated Time:** 30-60 minutes
**Risk Level:** Low (gradual migration, role column kept until end)

