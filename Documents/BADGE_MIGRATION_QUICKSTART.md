# Badge System Migration - Quick Start Guide

**Date:** February 15, 2026
**Status:** Ready to Execute
**Strategy:** Safe Parallel Migration (Keep role + Add badges)

---

## 🎯 Problem Solved

**Your Error:**
```
ERROR: cannot drop column role of table profiles because other objects depend on it
DETAIL: trigger auto_create_artist_profile on table profiles depends on column role
... (11 more dependencies)
```

**Root Cause:** You tried to drop `profiles.role` column, but triggers, RLS policies, and views still reference it.

**Solution:** Gradual migration strategy that keeps `role` column while adding badge system, then safely removes it after updating all dependencies.

---

## 📋 Migration Overview

**3-Phase Approach:**

### **Phase 1: Safe Migration** ✅ Ready
- Create `user_badges` table
- Add `primary_badge` and `all_badges` columns to profiles
- Keep `role` column (don't drop it yet!)
- Migrate existing data from role → badges
- Update `handle_new_user` trigger to create both role and badge

**File:** `20260215000000_badge_system_safe_migration.sql`
**Time:** 2-5 minutes
**Risk:** Low (additive only, no breaking changes)

---

### **Phase 2: Update Dependencies** ✅ Ready
- Update storage policies to use badges
- Update table policies to use badges
- Update Coliseum views/policies
- Verify no dependencies remain on `role` column

**File:** `20260215020000_badge_system_update_dependencies.sql`
**Time:** 2-5 minutes
**Risk:** Low (updates policies with equivalents)

---

### **Phase 3: Final Cleanup** ⚠️ Run Last
- Drop `role` column
- Remove sync trigger
- Verify badge system integrity
- Auto-repair any data issues

**File:** `20260215030000_badge_system_cleanup.sql`
**Time:** 1-2 minutes
**Risk:** Medium (irreversible, drops column)

---

## 🚀 Execution Steps

### **Step 1: Backup Database**
```bash
# In Supabase Dashboard → Database → Backups
# Or use pg_dump
pg_dump -h db.YOUR_PROJECT.supabase.co \
  -U postgres \
  -d postgres \
  --schema=public \
  --no-owner \
  --no-privileges \
  -f backup_before_badge_migration.sql
```

---

### **Step 2: Run Phase 1 (Safe Migration)**

**Option A: Via Supabase Dashboard (Recommended)**
1. Go to Supabase Dashboard → SQL Editor
2. Open file: `20260215000000_badge_system_safe_migration.sql`
3. Copy and paste entire contents
4. Click "Run"
5. Verify success: Should see "✅ Badge migration complete!" message

**Option B: Via CLI**
```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB

# Using Supabase CLI
supabase db push --file supabase/migrations/20260215000000_badge_system_safe_migration.sql
```

**Expected Output:**
```
✅ Badge migration complete!
📊 Created X badges from X profiles
⚠️  Note: role column still exists for backward compatibility
📝 Next: Update dependent policies/triggers to use badges, then drop role column
```

**Verify:**
```sql
-- Check badges created
SELECT user_id, badge_type, is_primary, verification_status
FROM user_badges
LIMIT 10;

-- Check profiles updated
SELECT id, role, primary_badge, all_badges
FROM profiles
LIMIT 10;

-- Expected: role, primary_badge should match
-- all_badges should contain [role]
```

---

### **Step 3: Test Badge System (Frontend)**

Before proceeding to Phase 2, verify badge system works:

1. **Create test hook in frontend:**
```typescript
// Test in browser console or component
import { supabase } from './lib/supabaseClient'

// Check your badges
const { data } = await supabase
  .from('user_badges')
  .select('*')
  .eq('user_id', 'YOUR_USER_ID')

console.log('My badges:', data)
```

2. **Test badge functions:**
```sql
-- Test in Supabase SQL Editor
SELECT user_has_badge('YOUR_USER_ID', 'fan'); -- Should return true
SELECT user_has_badge('YOUR_USER_ID', 'artist'); -- Depends on user
```

3. **Verify policies work:**
- Try accessing artist-only content (if you have artist badge)
- Should work exactly as before

---

### **Step 4: Run Phase 2 (Update Dependencies)**

**In Supabase Dashboard → SQL Editor:**
1. Open file: `20260215020000_badge_system_update_dependencies.sql`
2. Copy and paste entire contents
3. Click "Run"

**Expected Output:**
```
✅ Storage policies updated
✅ Table policies updated
✅ Coliseum policies updated
✅ Coliseum views updated
✅ All common dependencies updated!
📝 Next: Test badge system, then run 20260215030000_badge_system_cleanup.sql
```

**If warnings appear:**
```
⚠️ Dependencies still exist: X policies, X functions, X views
```

**Action:** Review `BADGE_MIGRATION_DEPENDENCY_UPDATE_GUIDE.md` for manual updates of custom policies.

---

### **Step 5: Verify Dependencies Updated**

Run this check:
```sql
-- Check for remaining dependencies on profiles.role
SELECT
  'Policy: ' || schemaname || '.' || tablename || ' -> ' || policyname as object
FROM pg_policies
WHERE pg_get_expr(qual, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%'
OR pg_get_expr(with_check, (schemaname||'.'||tablename)::regclass) ILIKE '%profiles.role%';

-- Expected: No rows (all updated)
```

**If rows returned:** Update those policies manually using the guide.

---

### **Step 6: Test Badge System Again**

Test thoroughly before dropping role column:

1. **Test badge switching:**
```sql
-- Switch your primary badge
SELECT set_primary_badge('YOUR_USER_ID', 'artist');

-- Verify switch worked
SELECT primary_badge, all_badges FROM profiles WHERE id = 'YOUR_USER_ID';
```

2. **Test RLS policies:**
- Upload content (should work if you have artist badge)
- Access brand profiles (should work if you have brand badge)
- Admin actions (should work if you have admin badge)

3. **Test in frontend:**
- Dashboard access with different badges
- Badge selector UI
- SmartRouteGuard with badge checks

---

### **Step 7: Run Phase 3 (Final Cleanup)**

**⚠️ WARNING: This is irreversible! Only proceed after:**
- [ ] Phase 1 completed successfully
- [ ] Phase 2 completed successfully
- [ ] All dependencies verified as updated
- [ ] Badge system tested and working
- [ ] Database backed up

**In Supabase Dashboard → SQL Editor:**
1. Open file: `20260215030000_badge_system_cleanup.sql`
2. **Read the safety checks** in the migration
3. Copy and paste entire contents
4. Click "Run"

**Expected Output:**
```
🔍 Checking for remaining dependencies on profiles.role...
✅ No dependencies found. Safe to proceed.
📦 Backed up X role records to temp table
✅ Sync trigger removed
✅ role column dropped from profiles table
✅ Badge system integrity verified
✅ Badge system repairs applied

════════════════════════════════════════
✅ BADGE SYSTEM MIGRATION COMPLETE!
════════════════════════════════════════
Total profiles: X
Users with badges: X
Total active badges: X
```

**If error occurs:**
```
ERROR: Cannot drop role column. Dependencies still exist: ...
```

**Action:** Abort! Review error message, update remaining dependencies, try again.

---

## ✅ Post-Migration Checklist

### **Database:**
- [ ] Verify `role` column removed from profiles
- [ ] Verify `user_badges` table populated
- [ ] Verify `primary_badge` and `all_badges` match expectations
- [ ] Test all RLS policies still work

### **Backend:**
- [ ] Update auth routes to use badges
- [ ] Update any backend logic checking `role`
- [ ] Test badge request API
- [ ] Test badge approval API

### **Frontend:**
- [ ] Implement `useBadges()` hook
- [ ] Build badge selector UI
- [ ] Update SmartRouteGuard to use badges
- [ ] Update dashboard routing
- [ ] Test badge switching
- [ ] Test dashboard access control

---

## 🚨 Troubleshooting

### **Issue: Migration fails with dependency error**
**Solution:** Don't use CASCADE. Follow the guide to update each dependency manually.

### **Issue: Users missing badges after migration**
**Solution:** Run repair query:
```sql
INSERT INTO user_badges (user_id, badge_type, is_primary, is_active, verification_status)
SELECT id, 'fan', true, true, 'verified'
FROM profiles
WHERE NOT EXISTS (
  SELECT 1 FROM user_badges WHERE user_id = profiles.id
);
```

### **Issue: primary_badge doesn't match user_badges**
**Solution:** Run sync query:
```sql
UPDATE profiles p
SET primary_badge = (
  SELECT badge_type FROM user_badges
  WHERE user_id = p.id AND is_primary = true LIMIT 1
);
```

### **Issue: RLS policies not working after migration**
**Solution:** Check if policy uses `all_badges` correctly:
```sql
-- Correct
'artist' = ANY(SELECT all_badges FROM profiles WHERE id = auth.uid())

-- Also correct (faster)
'artist' = ANY((SELECT all_badges FROM profiles WHERE id = auth.uid()))
```

---

## 📞 Emergency Rollback

**If badge system breaks production:**

1. **Restore role column:**
```sql
ALTER TABLE profiles ADD COLUMN role user_role;
UPDATE profiles SET role = primary_badge::user_role;
```

2. **Restore old policies:**
```sql
-- Recreate old policies from backup
-- (Keep backups of policy definitions before migration)
```

3. **Disable badge system:**
```sql
UPDATE user_badges SET is_active = false;
```

---

## 📊 Migration Timeline

**Estimated Total Time: 30-60 minutes**

| Phase | Time | Can Rollback? |
|-------|------|---------------|
| Backup | 5 min | N/A |
| Phase 1: Safe Migration | 5 min | ✅ Yes (harmless) |
| Testing | 10 min | ✅ Yes |
| Phase 2: Update Dependencies | 5 min | ✅ Yes (recreate policies) |
| Testing | 10 min | ✅ Yes |
| Phase 3: Final Cleanup | 2 min | ⚠️ Difficult |
| Verification | 5 min | - |

---

## ✅ Success Criteria

**Badge system is successfully migrated when:**
- ✅ All users have badges matching their previous roles
- ✅ Badge switching works in frontend
- ✅ All RLS policies use badges (not role)
- ✅ No errors in application logs
- ✅ `role` column removed from profiles
- ✅ New signups create badges automatically
- ✅ Badge request/approval flow works

---

## 📚 Related Documents

- **BADGE_AUTH_TREASURY_PRODUCTION_PLAN.md** - Full badge system architecture
- **BADGE_MIGRATION_DEPENDENCY_UPDATE_GUIDE.md** - Detailed dependency update instructions
- **Migration files:**
  - `20260215000000_badge_system_safe_migration.sql` - Phase 1
  - `20260215020000_badge_system_update_dependencies.sql` - Phase 2
  - `20260215030000_badge_system_cleanup.sql` - Phase 3

---

**Ready to start? Run Phase 1 migration now! 🚀**

**Questions?** Check the detailed guide or reach out for support.
