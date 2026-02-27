# Coliseum Complete Test Setup Guide

**Purpose:** Set up test data and verify end-to-end Coliseum Analytics flow  
**Time:** ~30 minutes  
**Status:** Ready to execute

---

## 🎯 Test Data Requirements

### Artists (4)
- **Test Artist Alpha** (Electronic) - 4 tracks
- **Test Artist Beta** (Indie Rock) - 4 tracks  
- **Test Artist Gamma** (Hip-Hop) - 4 tracks
- **Test Artist Delta** (Jazz) - 4 tracks

### Users (2)
- **Test User 1** - Heavy Alpha & Beta listener
- **Test User 2** - Heavy Gamma & Delta listener

### Simulated Plays
- User 1: 10 Alpha plays, 5 Beta plays, 1 Gamma play (16 total)
- User 2: 12 Gamma plays, 7 Delta plays, 1 Alpha play (20 total)
- **Total:** 36 passport events

### Expected Rankings (after processing)
1. **Test Artist Gamma** (12 plays from User 2)
2. **Test Artist Alpha** (10 plays from User 1)
3. **Test Artist Delta** (7 plays from User 2)
4. **Test Artist Beta** (5 plays from User 1)

---

## 📋 Quick Setup (Automated)

### Step 1: Run Test Data Scripts

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB

# Set database URL
export DATABASE_URL="postgresql://postgres:[PASSWORD]@[HOST]:[PORT]/postgres"

# Run complete test suite
./scripts/run_coliseum_test_suite.sh
```

**This will:**
1. ✅ Create 4 test artists
2. ✅ Create 16 test tracks (4 per artist)
3. ✅ Simulate 36 audio plays
4. ✅ Trigger Coliseum processor
5. ✅ Verify results and show leaderboard

### Step 2: Verify Frontend

```bash
# Start frontend (if not running)
cd /Users/pks.ml/Desktop/93/my-app
npm start

# Navigate to:
# - /catalog - Should show 4 test artists with tracks
# - /coliseum-dashboard - Should show rankings
```

---

## 🔍 Manual Setup (Step-by-Step)

### Step 1: Create Test Artists & Content

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
psql $DATABASE_URL -f scripts/create_coliseum_test_data.sql
```

**Verify:**
```sql
SELECT artist_name, COUNT(ci.id) as tracks
FROM artist_profiles ap
LEFT JOIN content_items ci ON ci.artist_id = ap.id
WHERE ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name;
```

**Expected:** 4 artists, 16 tracks total

### Step 2: Simulate Audio Plays

```bash
psql $DATABASE_URL -f scripts/simulate_audio_plays.sql
```

**Verify:**
```sql
SELECT 
  ap.artist_name,
  COUNT(*) as play_count
FROM passport_entries pe
JOIN artist_profiles ap ON ap.id = pe.entity_id
WHERE pe.event_type = 'player.track_played'
  AND ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name
ORDER BY play_count DESC;
```

**Expected:**
- Gamma: 12 plays
- Alpha: 10 plays
- Delta: 7 plays
- Beta: 5 plays

### Step 3: Deploy Updated Processor

```bash
# Deploy processor with enhanced weights
supabase functions deploy coliseum-processor
```

**Verify deployment:**
```bash
curl -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json"
```

### Step 4: Trigger Processor

```bash
# Get service key
SERVICE_KEY=$(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d '=' -f2 | tr -d '"')

# Trigger
curl -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json"
```

**Expected Response:**
```json
{
  "success": true,
  "processed": 36,
  "mutations_generated": 144,
  "artists_recalculated": 4,
  "processing_time_ms": 1234
}
```

### Step 5: Verify Results

```bash
psql $DATABASE_URL -f scripts/verify_coliseum_test_data.sql
```

**Check Leaderboard:**
```sql
SELECT 
  ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as rank,
  artist_name,
  ROUND(domain_strength, 2) as strength
FROM coliseum_leaderboard_t_7d
WHERE artist_name LIKE 'Test Artist%'
ORDER BY domain_strength DESC;
```

**Expected Rankings:**
1. Test Artist Gamma
2. Test Artist Alpha
3. Test Artist Delta
4. Test Artist Beta

---

## 🎨 Frontend Verification

### Catalog Page (`/catalog`)

**Expected:**
- ✅ 4 test artists displayed
- ✅ Each artist shows 4 tracks
- ✅ Tracks are playable
- ✅ Artist names match: Alpha, Beta, Gamma, Delta

### Coliseum Dashboard (`/coliseum-dashboard` or `/coliseum`)

**Expected:**
- ✅ Leaderboard displays 4 artists
- ✅ Rankings match expected order:
  1. Test Artist Gamma
  2. Test Artist Alpha
  3. Test Artist Delta
  4. Test Artist Beta
- ✅ Domain selector works (A/T/G/C/Composite)
- ✅ Time range selector works (7d/30d/alltime)
- ✅ Strength values displayed correctly

---

## 🧪 E2E Testing Integration

### Align with E2E Test Plan

The test data setup aligns with the E2E test requirements:

1. **User Activity / Login** ✅
   - Test users available for E2E tests
   - Can authenticate and create sessions

2. **Simulate Play for Artist** ✅
   - Test tracks available in catalog
   - Can be played via AudioPlayerContext

3. **Log Play to Passport** ✅
   - Passport events created with correct structure
   - Includes artistId, trackId, platform metadata

4. **Affect Artist Ranking** ✅
   - Processor creates mutations
   - Domain strength updates
   - Rankings change based on plays

5. **Listening History** ✅
   - Events logged to passport_entries
   - Can be queried for history

### Run E2E Tests

```bash
cd /Users/pks.ml/Desktop/93/my-app

# Run full audio flow test
npx playwright test tests/e2e/full-audio-flow.spec.ts

# Run with UI (for debugging)
npx playwright test tests/e2e/full-audio-flow.spec.ts --ui
```

---

## 🔧 Weight System Verification

### Tiered Weights Implemented

The processor now applies tiered weights:

- **TIER 1 (0.1x):** Low engagement (<30% completion)
- **TIER 2 (1.0x):** Standard play (30-80% completion)
- **TIER 3 (10.0x):** High engagement (>80% completion OR repeat play)

### Verify Weights Applied

```sql
-- Check weight distribution
SELECT 
  CASE 
    WHEN weight = 0.1 THEN 'TIER 1 (Low)'
    WHEN weight = 1.0 THEN 'TIER 2 (Standard)'
    WHEN weight = 10.0 THEN 'TIER 3 (High)'
    ELSE 'Other'
  END as tier,
  COUNT(*) as mutation_count,
  ROUND(SUM(effective_delta), 2) as total_strength
FROM coliseum_dna_mutations
WHERE artist_id IN (
  SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
)
GROUP BY tier
ORDER BY tier;
```

**Expected:**
- TIER 1: Some mutations (low completion plays)
- TIER 2: Most mutations (standard plays)
- TIER 3: Some mutations (high completion/repeat plays)

---

## 📊 Test Scenarios

### Scenario 1: Basic Play Tracking
1. User plays track
2. Event logged to Passport
3. Processor creates mutations
4. Artist ranking increases

### Scenario 2: Weighted Plays
1. User plays track to 90% completion → TIER 3 weight (10x)
2. User plays same track again → TIER 3 weight (repeat play)
3. User plays track to 20% completion → TIER 1 weight (0.1x)
4. Verify rankings reflect weighted plays

### Scenario 3: Multiple Artists
1. User plays tracks from 4 different artists
2. All artists get mutations
3. Rankings reflect play distribution
4. Leaderboard shows all 4 artists

### Scenario 4: Progressive Ranking
1. Record initial ranking
2. User plays track 5 times
3. Verify ranking increases progressively
4. Each play adds to total strength

---

## ✅ Success Criteria

Test setup is successful when:

- [x] 4 test artists created
- [x] 16 tracks created (4 per artist)
- [x] 36 passport events created
- [x] Mutations created for all artists
- [x] Domain strength calculated
- [x] Leaderboard shows 4 artists
- [x] Rankings match expected order
- [x] Frontend catalog shows artists
- [x] Frontend leaderboard shows rankings
- [x] Weight system working correctly
- [x] E2E tests can run successfully

---

## 🐛 Troubleshooting

### Issue: Artists Not in Catalog

**Check:**
```sql
SELECT 
  ap.artist_name,
  ci.title,
  ci.is_published
FROM artist_profiles ap
LEFT JOIN content_items ci ON ci.artist_id = ap.id
WHERE ap.artist_name LIKE 'Test Artist%';
```

**Fix:** Ensure `is_published = true` for all tracks

### Issue: Rankings Don't Match Expected

**Check:**
```sql
-- Compare play counts vs rankings
WITH play_counts AS (
  SELECT 
    ap.artist_name,
    COUNT(*) as play_count
  FROM passport_entries pe
  JOIN artist_profiles ap ON ap.id = pe.entity_id
  WHERE pe.event_type = 'player.track_played'
    AND ap.artist_name LIKE 'Test Artist%'
  GROUP BY ap.id, ap.artist_name
),
rankings AS (
  SELECT 
    artist_name,
    ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as rank
  FROM coliseum_leaderboard_t_7d
  WHERE artist_name LIKE 'Test Artist%'
)
SELECT 
  pc.artist_name,
  pc.play_count,
  r.rank,
  CASE WHEN pc.play_count = (SELECT MAX(play_count) FROM play_counts) AND r.rank = 1 THEN '✅' ELSE '⚠️' END as match
FROM play_counts pc
JOIN rankings r ON r.artist_name = pc.artist_name
ORDER BY pc.play_count DESC;
```

**Possible Causes:**
- Weights not applied correctly
- Recency decay affecting older plays
- Processor not processing all events

---

## 🚀 Next Steps

After test data is set up:

1. **Verify Frontend:**
   - Check `/catalog` shows 4 artists
   - Check `/coliseum-dashboard` shows rankings

2. **Run E2E Tests:**
   ```bash
   npx playwright test tests/e2e/full-audio-flow.spec.ts
   ```

3. **Test Real Plays:**
   - Play tracks in frontend
   - Verify events logged
   - Check rankings update

4. **Monitor Processing:**
   - Verify CRON runs every 5 minutes
   - Check events processed automatically
   - Monitor leaderboard updates

---

**Status:** Ready to execute! 🎉

**Files Created:**
- `scripts/create_coliseum_test_data.sql` - Creates artists and content
- `scripts/simulate_audio_plays.sql` - Simulates plays
- `scripts/verify_coliseum_test_data.sql` - Verification queries
- `scripts/run_coliseum_test_suite.sh` - Automated test suite
- `Documents/COLISEUM_TEST_DATA_GUIDE.md` - Detailed guide
- `Documents/COLISEUM_COMPLETE_TEST_SETUP.md` - This file
