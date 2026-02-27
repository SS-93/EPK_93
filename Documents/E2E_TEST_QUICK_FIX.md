# E2E Test Quick Fix Guide

**Issue:** Invalid API Key Error  
**Fix Time:** ~5 minutes

---

## 🔴 Problem

Tests failing with: `AuthApiError: Invalid API key`

---

## ✅ Quick Fix Steps

### Step 1: Get Fresh Service Role Key

1. Go to: https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/settings/api
2. Scroll to "Project API keys"
3. Find "service_role" key (click "Reveal" if hidden)
4. Copy the entire key

### Step 2: Update .env File

```bash
cd /Users/pks.ml/Desktop/93/my-app

# Edit .env file
nano .env  # or use your preferred editor

# Update this line:
SUPABASE_SERVICE_ROLE_KEY=<paste-new-key-here>
```

### Step 3: Verify Key Works

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
  .then(r => {
    if (r.error) {
      console.log('❌ Key Invalid:', r.error.message);
    } else {
      console.log('✅ Key Valid!');
    }
  });
"
```

**Expected:** `✅ Key Valid!`

### Step 4: Re-run Tests

```bash
cd /Users/pks.ml/Desktop/93/my-app

export REACT_APP_SUPABASE_URL="https://iutnwgvzwyupsuguxnls.supabase.co"
export REACT_APP_SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml1dG53Z3Z6d3l1cHN1Z3V4bmxzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk1MzQ4MTgsImV4cCI6MjA2NTExMDgxOH0.aC_YpMkzDJrhgf2KkGf2iFB6kZeCUCEk9dm-disMT7U"
export SUPABASE_SERVICE_ROLE_KEY="<your-new-key-here>"

npx playwright test tests/e2e/full-audio-flow.spec.ts --ui
```

---

## 🔍 Alternative: Use Signup Instead of Admin API

If service role key continues to fail, modify test to use signup:

**File:** `tests/e2e/full-audio-flow.spec.ts`

**Change:**
```typescript
// OLD (line 35-39):
const { data: userData, error: userError } = await supabaseService.auth.admin.createUser({
  email: testUserEmail,
  password: 'test-password-123',
  email_confirm: true
});

// NEW:
const { data: userData, error: userError } = await supabaseAnon.auth.signUp({
  email: testUserEmail,
  password: 'test-password-123',
  options: {
    email_redirect_to: undefined // Skip email confirmation for tests
  }
});
```

**Note:** This requires email confirmation to be disabled in Supabase Auth settings for test emails.

---

## 📊 Current Test Status

- **Tests Run:** 2
- **Tests Passed:** 0
- **Tests Failed:** 2
- **Error:** Invalid API key
- **Fix Applied:** dotenv loading ✅
- **Remaining:** Update service role key

---

**Next Action:** Get fresh key from Supabase Dashboard and update .env file
