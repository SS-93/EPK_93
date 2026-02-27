# Coliseum E2E Testing Integration Guide

**Purpose:** Align test data setup with E2E testing requirements  
**Status:** Ready for integration  
**Date:** February 3, 2026

---

## 🎯 Overview

This guide integrates:
1. **Test Data Scripts** (SQL-based, for manual/CI testing)
2. **E2E Test Suite** (Playwright-based, automated testing)
3. **Frontend Verification** (Manual UI testing)

---

## 📋 E2E Test Structure (from `full-audio-flow.spec.ts`)

### Test Flow
```
1. User Login & Authentication ✅
2. Navigate to Test Harness (/test-passport) ✅
3. Capture Passport Events ✅
4. Simulate Play Event (via test harness button) ✅
5. Verify Passport Entry in Database ✅
6. Trigger Coliseum Processor ✅
7. Verify DNA Mutations Created ✅
8. Verify Artist Ranking Updated ✅
9. Verify Listening History ✅
10. Verify Leaderboard UI Updates ✅
```

### Test Data Created Per Test
- **User:** Created in `beforeAll` with unique email
- **Artist:** Created per test run
- **Track:** Created per test run
- **Cleanup:** All removed in `afterAll`

### Test Harness Used
- **Route:** `/test-passport`
- **Component:** Uses `PassportTest` component
- **Button:** `btn-log-play` test ID
- **Note:** Uses hardcoded `test-artist-456` ID

---

## 🔄 Integration Strategy

### Option 1: Use E2E Test Data (Recommended for E2E)

The E2E test creates its own data, so:
- ✅ No manual test data needed for E2E tests
- ✅ Each test run is isolated
- ✅ Cleanup happens automatically

**Run E2E Tests:**
```bash
cd /Users/pks.ml/Desktop/93/my-app
npx playwright test tests/e2e/full-audio-flow.spec.ts
```

### Option 2: Use SQL Test Data (Recommended for Manual Testing)

For manual testing and catalog verification:
- ✅ Use SQL scripts to create persistent test data
- ✅ 4 artists, 16 tracks visible in catalog
- ✅ Can manually play tracks and verify rankings

**Run SQL Scripts:**
```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
./scripts/run_coliseum_test_suite.sh
```

### Option 3: Hybrid Approach (Best for Complete Testing)

1. **SQL Scripts:** Create persistent test data for catalog/UI
2. **E2E Tests:** Create isolated test data for automated testing
3. **Both coexist:** SQL data for manual testing, E2E data for automation

---

## 🎨 Test Data Alignment

### E2E Test Requirements

From `full-audio-flow.spec.ts`:
- ✅ User with email/password
- ✅ Artist profile with `user_id` link
- ✅ Track with `artist_id` link
- ✅ Passport events with `artistId` in metadata

### SQL Test Data Requirements

From `create_coliseum_test_data.sql`:
- ✅ 4 artists (Alpha, Beta, Gamma, Delta)
- ✅ 16 tracks (4 per artist)
- ✅ Published tracks (`is_published = true`)
- ✅ Genre metadata for A-domain mutations

### Alignment Checklist

- [x] Both create artists in `artist_profiles`
- [x] Both create tracks in `content_items`
- [x] Both use `is_published = true`
- [x] Both include `artist_id` in tracks
- [x] E2E uses test harness, SQL uses direct Passport inserts
- [x] Both trigger Coliseum processor
- [x] Both verify mutations and rankings

---

## 🔧 E2E Test Enhancements Needed

### Issue 1: Hardcoded Artist ID

**Current:** E2E test uses `test-artist-456` (from PassportTest component)

**Solution:** Update PassportTest component to use test artist ID, OR update E2E test to use created artist ID

**File:** `src/routes/test-passport.tsx` (or wherever PassportTest is)

**Change:**
```typescript
// Instead of hardcoded 'test-artist-456'
const testArtistId = props.artistId || 'test-artist-456';
```

### Issue 2: Test Harness Route

**Current:** E2E test navigates to `/test-passport`

**Verify:** Ensure this route exists and has the test harness component

**Check:**
```bash
# Search for test-passport route
grep -r "test-passport" src/routes/
```

### Issue 3: Listening History

**Current:** E2E test checks but doesn't require listening history

**Note:** PassportTest bypasses AudioPlayerContext, so listening history won't be logged

**Solution:** This is expected behavior - test verifies Passport logging, not full AudioPlayerContext flow

---

## 📊 Test Scenarios

### Scenario 1: E2E Automated Test

**Purpose:** Verify complete flow works end-to-end

**Steps:**
1. Run: `npx playwright test tests/e2e/full-audio-flow.spec.ts`
2. Test creates its own data
3. Test verifies all steps
4. Test cleans up automatically

**Expected:** All 10 steps pass

### Scenario 2: Manual Catalog Testing

**Purpose:** Verify catalog shows test artists

**Steps:**
1. Run SQL scripts to create test data
2. Start frontend: `npm start`
3. Navigate to `/catalog`
4. Verify 4 test artists appear
5. Verify each has 4 tracks

**Expected:** Catalog displays test data

### Scenario 3: Manual Leaderboard Testing

**Purpose:** Verify leaderboard shows rankings

**Steps:**
1. Run SQL scripts (includes simulated plays)
2. Trigger processor manually
3. Navigate to `/coliseum-dashboard`
4. Verify rankings match expected order

**Expected:** Leaderboard shows correct rankings

### Scenario 4: Real Play Testing

**Purpose:** Verify real audio plays affect rankings

**Steps:**
1. Use SQL test data (artists/tracks exist)
2. Play tracks in frontend
3. Wait for CRON or trigger processor manually
4. Check leaderboard updates

**Expected:** Rankings update based on plays

---

## 🧪 Running Tests

### E2E Tests (Automated)

```bash
cd /Users/pks.ml/Desktop/93/my-app

# Run full audio flow test
npx playwright test tests/e2e/full-audio-flow.spec.ts

# Run with UI (for debugging)
npx playwright test tests/e2e/full-audio-flow.spec.ts --ui

# Run with headed browser
npx playwright test tests/e2e/full-audio-flow.spec.ts --headed

# Run specific test
npx playwright test tests/e2e/full-audio-flow.spec.ts -g "Complete flow"
```

### SQL Test Data (Manual)

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB

# Set database URL
export DATABASE_URL="postgresql://..."

# Run complete test suite
./scripts/run_coliseum_test_suite.sh

# Or run individually
psql $DATABASE_URL -f scripts/create_coliseum_test_data.sql
psql $DATABASE_URL -f scripts/simulate_audio_plays.sql
psql $DATABASE_URL -f scripts/verify_coliseum_test_data.sql
```

### Frontend Manual Testing

```bash
cd /Users/pks.ml/Desktop/93/my-app

# Start frontend
npm start

# Navigate to:
# - http://localhost:3000/catalog (verify artists)
# - http://localhost:3000/coliseum-dashboard (verify rankings)
# - http://localhost:3000/test-passport (test harness)
```

---

## ✅ Verification Checklist

### E2E Test Verification

- [ ] Test file exists: `tests/e2e/full-audio-flow.spec.ts`
- [ ] Test harness route exists: `/test-passport`
- [ ] Test harness has `btn-log-play` button
- [ ] Test creates user, artist, track
- [ ] Test captures Passport events
- [ ] Test triggers processor
- [ ] Test verifies mutations
- [ ] Test verifies rankings
- [ ] Test cleans up data

### SQL Test Data Verification

- [ ] Scripts create 4 artists
- [ ] Scripts create 16 tracks
- [ ] Scripts simulate 36 plays
- [ ] Scripts trigger processor
- [ ] Scripts verify results
- [ ] Catalog shows test artists
- [ ] Leaderboard shows rankings

### Integration Verification

- [ ] E2E tests run successfully
- [ ] SQL test data visible in catalog
- [ ] Both can coexist
- [ ] Rankings update correctly
- [ ] No conflicts between test data

---

## 🔍 Troubleshooting

### Issue: E2E Test Fails - Test Harness Not Found

**Symptoms:** Test can't find `/test-passport` route

**Solution:**
1. Check if route exists in router
2. Verify PassportTest component exists
3. Check route configuration

### Issue: E2E Test Fails - Artist ID Mismatch

**Symptoms:** Test creates artist but PassportTest uses different ID

**Solution:**
1. Update PassportTest to accept artist ID prop
2. Or update E2E test to use `test-artist-456`
3. Or create `test-artist-456` profile in database

### Issue: SQL Test Data Not Visible in Catalog

**Symptoms:** Artists created but not showing in frontend

**Solution:**
1. Check `is_published = true` for tracks
2. Verify RLS policies allow read access
3. Check frontend query filters

### Issue: Rankings Don't Match Expected

**Symptoms:** Leaderboard shows different order than expected

**Solution:**
1. Check play counts match expected
2. Verify weights applied correctly
3. Check time range (7d vs 30d vs alltime)
4. Verify materialized views refreshed

---

## 📝 Next Steps

### Immediate Actions

1. **Verify E2E Test Setup:**
   ```bash
   cd /Users/pks.ml/Desktop/93/my-app
   npx playwright test tests/e2e/full-audio-flow.spec.ts --ui
   ```

2. **Run SQL Test Data:**
   ```bash
   cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
   ./scripts/run_coliseum_test_suite.sh
   ```

3. **Verify Integration:**
   - Check catalog shows SQL test data
   - Run E2E test (creates its own data)
   - Verify both work independently

### Enhancements

1. **Update PassportTest Component:**
   - Accept artist ID as prop
   - Use test artist ID from E2E test
   - Remove hardcoded `test-artist-456`

2. **Add More E2E Scenarios:**
   - Multiple artists test
   - Progressive ranking test (already exists)
   - Weight verification test
   - Time range test

3. **Create Test Data Fixtures:**
   - Shared test data for both E2E and SQL
   - Consistent artist/track IDs
   - Reusable across test types

---

## 📚 Reference Files

### E2E Test Files
- `tests/e2e/full-audio-flow.spec.ts` - Main E2E test
- `tests/helpers/test-setup.ts` - Test utilities
- `tests/helpers/test-users.ts` - Test user definitions
- `playwright.config.ts` - Playwright configuration

### SQL Test Scripts
- `scripts/create_coliseum_test_data.sql` - Create artists/tracks
- `scripts/simulate_audio_plays.sql` - Simulate plays
- `scripts/verify_coliseum_test_data.sql` - Verification queries
- `scripts/run_coliseum_test_suite.sh` - Automated suite

### Documentation
- `E2E_TEST_VERIFICATION_PLAN.md` - E2E test plan
- `TEST_EXECUTION_SUMMARY.md` - Test execution guide
- `COLISEUM_COMPLETE_TEST_SETUP.md` - Complete setup guide
- This file - Integration guide

---

**Status:** Ready for integration testing! 🚀
