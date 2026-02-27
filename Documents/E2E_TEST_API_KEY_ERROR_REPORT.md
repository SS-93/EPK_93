# E2E Test API Key Error - Detailed Report

**Date:** February 3, 2026  
**Test File:** `tests/e2e/full-audio-flow.spec.ts`  
**Status:** ❌ FAILED - Invalid API Key  
**Tests Executed:** 2  
**Tests Passed:** 0  
**Tests Failed:** 2

---

## 🔴 Error Summary

### Primary Error: Invalid API Key

```
AuthApiError: Invalid API key
  at handleError (/Users/pks.ml/Desktop/93/my-app/node_modules/@supabase/auth-js/src/lib/fetch.ts:102:9)
  at GoTrueAdminApi.createUser (/Users/pks.ml/Desktop/93/my-app/node_modules/@supabase/auth-js/src/GoTrueAdminApi.ts:162:14)
  at /Users/pks.ml/Desktop/93/my-app/tests/e2e/full-audio-flow.spec.ts:49:50
```

**Location:** Test setup phase (`test.beforeAll()`)  
**Operation:** Creating test user via Supabase Admin API  
**Impact:** Both tests failed before execution could begin

### Secondary Error: Invalid UUID

```
Error: @supabase/auth-js: Expected parameter to be UUID but is not
  at validateUUID (/Users/pks.ml/Desktop/93/my-app/node_modules/@supabase/auth-js/src/lib/helpers.ts:365:11)
  at GoTrueAdminApi.deleteUser (/Users/pks.ml/Desktop/93/my-app/node_modules/@supabase/auth-js/src/GoTrueAdminApi.ts:281:17)
  at /Users/pks.ml/Desktop/93/my-app/tests/e2e/full-audio-flow.spec.ts:143:38
```

**Location:** Test cleanup phase (`test.afterAll()`)  
**Operation:** Deleting test user  
**Root Cause:** Cascading error - `testUserId` is undefined because user creation failed

---

## 🔍 Detailed Error Analysis

### Error 1: Invalid API Key

**What Happened:**
- Test attempts to create a user using Supabase Admin API
- API call fails with "Invalid API key" error
- User creation fails, preventing test from proceeding

**Code Location:**
```typescript
// Line 49 in full-audio-flow.spec.ts
const { data: userData, error: userError } = await supabaseService.auth.admin.createUser({
  email: testUserEmail,
  password: 'test-password-123',
  email_confirm: true
});
```

**API Key Used:**
- Environment Variable: `SUPABASE_SERVICE_ROLE_KEY`
- Value: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` (from .env file)
- Expected Format: JWT token with `service_role` claim

**Possible Causes:**

1. **Key Expired or Rotated**
   - Supabase service role keys can be rotated
   - Key may have been regenerated in dashboard
   - Key timestamp: `iat:1749534818` (check if expired)

2. **Key Format Issue**
   - Key may have extra whitespace
   - Key may be truncated
   - Key may be from different project

3. **Environment Variable Not Loaded**
   - Playwright may not load `.env` automatically
   - Variable name mismatch
   - File path issue

4. **Project Mismatch**
   - Key may be for different Supabase project
   - Project ref mismatch: `iutnwgvzwyupsuguxnls`

---

## 🔧 Diagnostic Steps Performed

### Step 1: Verify Environment Variables

```bash
# Check .env file
cd /Users/pks.ml/Desktop/93/my-app
cat .env | grep SUPABASE_SERVICE_ROLE_KEY
```

**Result:** ✅ Key exists in .env file

### Step 2: Verify Key Format

```bash
# Check key length and format
node -e "require('dotenv').config(); console.log('Key length:', process.env.SUPABASE_SERVICE_ROLE_KEY?.length);"
```

**Result:** ✅ Key format appears correct (JWT token)

### Step 3: Test Key Validity

```bash
# Attempt to use key directly
node -e "
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();
const supabase = createClient(
  process.env.REACT_APP_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);
supabase.auth.admin.listUsers({ page: 1, perPage: 1 })
  .then(r => console.log('Result:', r.error ? 'FAILED: ' + r.error.message : 'SUCCESS'))
  .catch(e => console.log('Error:', e.message));
"
```

**Result:** ❌ Key validation test failed

---

## 📊 Test Execution Timeline

### Test Run 1 (Background Process)
- **Started:** ~1:52 AM
- **Status:** Failed during setup
- **Duration:** ~30 seconds
- **Failure Point:** User creation

### Test Run 2 (After Fix)
- **Started:** After dotenv fix
- **Status:** Failed during setup
- **Duration:** ~30 seconds
- **Failure Point:** User creation (same error)

---

## 🎯 Root Cause Analysis

### Most Likely Cause: Invalid or Expired Service Role Key

**Evidence:**
1. ✅ Key exists in .env file
2. ✅ Key format is correct (JWT)
3. ❌ Key fails authentication test
4. ❌ Admin API calls fail with "Invalid API key"

**Conclusion:** The service role key in the .env file is either:
- Expired/rotated
- From a different project
- Missing required permissions
- Incorrectly copied (truncated or extra characters)

---

## 🔧 Solutions

### Solution 1: Get Fresh Service Role Key (RECOMMENDED)

**Steps:**
1. Go to Supabase Dashboard: https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/settings/api
2. Scroll to "Project API keys" section
3. Find "service_role" key (secret, hidden by default)
4. Click "Reveal" or "Reset" to get fresh key
5. Copy the key
6. Update `.env` file:
   ```bash
   SUPABASE_SERVICE_ROLE_KEY=<new-key-here>
   ```

### Solution 2: Verify Key Permissions

**Check:**
- Key has `service_role` claim (not `anon`)
- Key is for correct project (`iutnwgvzwyupsuguxnls`)
- Key hasn't been disabled in dashboard

### Solution 3: Alternative Test Approach

**If key issues persist, use alternative method:**

```typescript
// Instead of admin.createUser, use signup flow
const { data: authData, error: authError } = await supabaseAnon.auth.signUp({
  email: testUserEmail,
  password: 'test-password-123',
});

if (authError) throw authError;
testUserId = authData.user!.id;
```

**Pros:**
- Doesn't require service role key
- Uses public API
- More realistic user flow

**Cons:**
- Requires email confirmation (can be disabled in Supabase)
- May need to handle existing user errors

---

## 📝 Test File Fixes Applied

### Fix 1: Explicit dotenv Loading ✅

```typescript
import { config } from 'dotenv';
import { resolve } from 'path';

config({ path: resolve(__dirname, '../../.env') });
```

**Status:** ✅ Applied

### Fix 2: Environment Variable Validation ✅

```typescript
if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY || !SUPABASE_ANON_KEY) {
  throw new Error('Missing required Supabase environment variables. Check .env file.');
}

if (SUPABASE_SERVICE_KEY.includes('your-') || SUPABASE_SERVICE_KEY.length < 100) {
  throw new Error('SUPABASE_SERVICE_ROLE_KEY appears invalid. Get fresh key from Supabase Dashboard.');
}
```

**Status:** ✅ Applied

### Fix 3: Error Handling in Cleanup ✅

```typescript
test.afterAll(async () => {
  // Only cleanup if user was created successfully
  if (testUserId && testUserId.match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)) {
    await supabaseService.auth.admin.deleteUser(testUserId);
  }
});
```

**Status:** ⏳ Needs to be applied

---

## 📊 Test Results Summary

### Test 1: Complete Flow
- **Status:** ❌ FAILED
- **Error:** Invalid API key
- **Failed At:** User creation (beforeAll)
- **Progress:** 0% (didn't start)

### Test 2: Progressive Ranking
- **Status:** ❌ FAILED
- **Error:** Invalid API key
- **Failed At:** User creation (beforeAll)
- **Progress:** 0% (didn't start)

### Overall Test Suite
- **Total Tests:** 2
- **Passed:** 0 (0%)
- **Failed:** 2 (100%)
- **Skipped:** 0
- **Duration:** ~30 seconds (failed quickly)

---

## 🎯 Next Steps

### Immediate Actions Required

1. **Get Fresh Service Role Key:**
   - Dashboard: https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/settings/api
   - Copy "service_role" key
   - Update `.env` file

2. **Verify Key Works:**
   ```bash
   cd /Users/pks.ml/Desktop/93/my-app
   node -e "
   require('dotenv').config();
   const { createClient } = require('@supabase/supabase-js');
   const supabase = createClient(
     process.env.REACT_APP_SUPABASE_URL,
     process.env.SUPABASE_SERVICE_ROLE_KEY
   );
   supabase.auth.admin.listUsers({ page: 1, perPage: 1 })
     .then(r => console.log(r.error ? 'FAILED: ' + r.error.message : 'SUCCESS'))
   "
   ```

3. **Re-run Tests:**
   ```bash
   npx playwright test tests/e2e/full-audio-flow.spec.ts --ui
   ```

### Alternative: Use Signup Flow

If service role key issues persist, modify test to use signup instead of admin API:

```typescript
// Replace admin.createUser with signup
const { data: authData, error: authError } = await supabaseAnon.auth.signUp({
  email: testUserEmail,
  password: 'test-password-123',
});
```

---

## 📋 Verification Checklist

Before re-running tests, verify:

- [ ] Fresh service role key obtained from Supabase Dashboard
- [ ] Key updated in `.env` file
- [ ] Key validation test passes
- [ ] Test file has dotenv loading
- [ ] Test file has error handling
- [ ] Environment variables exported correctly

---

## 🔍 Additional Diagnostics

### Check Key Claims

The service role key should have:
- `role: "service_role"` (not "anon")
- `ref: "iutnwgvzwyupsuguxnls"` (matches project)
- Valid expiration (`exp` claim)

### Decode JWT (for debugging)

```bash
# Decode JWT payload (base64)
echo "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1dG53Z3Z6d3l1cHN1Z3V4bmxzIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc0OTUzNDgxOCwiZXhwIjoyMDY1MTEwODE4fQ" | base64 -d
```

**Expected Output:**
```json
{
  "iss": "supabase",
  "ref": "iutnwgvzwyupsuguxnls",
  "role": "service_role",
  "iat": 1749534818,
  "exp": 2065110818
}
```

---

## 📊 Impact Assessment

### What's Blocked

- ❌ E2E test execution
- ❌ Automated user creation
- ❌ Full flow verification
- ❌ Progressive ranking test

### What Still Works

- ✅ Test file structure
- ✅ Playwright configuration
- ✅ Environment variable loading (after fix)
- ✅ Test logic (not yet executed)

---

## 🚀 Recommended Action Plan

### Priority 1: Fix API Key (5 minutes)

1. Get fresh key from Supabase Dashboard
2. Update `.env` file
3. Verify key works
4. Re-run tests

### Priority 2: Improve Error Handling (10 minutes)

1. Add better error messages
2. Add key validation
3. Add fallback to signup flow
4. Improve cleanup error handling

### Priority 3: Test Alternative Approaches (15 minutes)

1. Test signup flow as alternative
2. Test with different authentication methods
3. Document working approach

---

**Status:** ❌ Tests failed due to invalid API key  
**Action Required:** Get fresh service role key from Supabase Dashboard  
**Estimated Fix Time:** ~5 minutes  
**Next:** Update key and re-run tests
