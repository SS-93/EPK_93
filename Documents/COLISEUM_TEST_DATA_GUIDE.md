# Coliseum Test Data Setup Guide

**Purpose:** Create test data for Coliseum Analytics Engine  
**Time:** ~15 minutes  
**Status:** Ready to execute

---

## 🎯 Test Data Requirements

### Artists (4)
- Test Artist Alpha (Electronic)
- Test Artist Beta (Indie Rock)
- Test Artist Gamma (Hip-Hop)
- Test Artist Delta (Jazz)

### Content (16 tracks)
- 4 tracks per artist
- Different genres/styles
- Published and ready to play

### Users (2)
- Test User 1 (Heavy Alpha & Beta listener)
- Test User 2 (Heavy Gamma & Delta listener)

### Simulated Plays
- User 1: 10 Alpha plays, 5 Beta plays, 1 Gamma play
- User 2: 12 Gamma plays, 7 Delta plays, 1 Alpha play

**Expected Rankings (after processing):**
1. Test Artist Gamma (12 plays)
2. Test Artist Alpha (10 plays)
3. Test Artist Delta (7 plays)
4. Test Artist Beta (5 plays)

---

## 📋 Setup Steps

### Option 1: Automated Script (Recommended)

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB

# Set DATABASE_URL
export DATABASE_URL="postgresql://postgres:[PASSWORD]@[HOST]:[PORT]/postgres"

# Run complete test suite
./scripts/run_coliseum_test_suite.sh
```

This will:
1. ✅ Create 4 test artists
2. ✅ Create 16 test tracks (4 per artist)
3. ✅ Simulate audio plays from 2 users
4. ✅ Trigger Coliseum processor
5. ✅ Verify results and show leaderboard

### Option 2: Manual Step-by-Step

#### Step 1: Create Test Data

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB

# Run SQL script
psql $DATABASE_URL -f scripts/create_coliseum_test_data.sql
```

**Expected Output:**
- 4 artists created
- 16 tracks created (4 per artist)
- Verification queries show counts

#### Step 2: Simulate Audio Plays

```bash
# Run simulation script
psql $DATABASE_URL -f scripts/simulate_audio_plays.sql
```

**Expected Output:**
- 36 passport events created
- Distribution:
  - User 1: 16 plays (10 Alpha, 5 Beta, 1 Gamma)
  - User 2: 20 plays (12 Gamma, 7 Delta, 1 Alpha)

#### Step 3: Trigger Processor

```bash
# Get service role key
SERVICE_KEY=$(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d '=' -f2 | tr -d '"')

# Trigger processor
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

#### Step 4: Verify Results

```bash
# Run verification script
psql $DATABASE_URL -f scripts/verify_coliseum_test_data.sql
```

**Expected Output:**
- Mutations created for all 4 artists
- Domain strength calculated
- Leaderboard rankings match expected order

---

## 🔍 Verification Queries

### Check Test Data

```sql
-- Artists
SELECT artist_name FROM artist_profiles WHERE artist_name LIKE 'Test Artist%';

-- Content
SELECT 
  ap.artist_name,
  COUNT(ci.id) as track_count
FROM artist_profiles ap
LEFT JOIN content_items ci ON ci.artist_id = ap.id
WHERE ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name;
```

### Check Passport Events

```sql
-- Play distribution
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

### Check Mutations

```sql
-- Mutations by artist
SELECT 
  ap.artist_name,
  domain,
  COUNT(*) as mutation_count,
  ROUND(SUM(effective_delta), 2) as total_strength
FROM coliseum_dna_mutations cm
JOIN artist_profiles ap ON ap.id = cm.artist_id
WHERE ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name, domain
ORDER BY ap.artist_name, domain;
```

### Check Leaderboard

```sql
-- T-Domain Leaderboard (should reflect play counts)
SELECT 
  ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as rank,
  artist_name,
  ROUND(domain_strength, 2) as strength
FROM coliseum_leaderboard_t_7d
WHERE artist_name LIKE 'Test Artist%'
ORDER BY domain_strength DESC;
```

**Expected Rankings:**
1. Test Artist Gamma (12 plays)
2. Test Artist Alpha (10 plays)
3. Test Artist Delta (7 plays)
4. Test Artist Beta (5 plays)

---

## 🎨 Frontend Verification

### Check Catalog

1. Navigate to `/catalog` in frontend
2. Verify 4 test artists appear
3. Each artist should have 4 tracks
4. Tracks should be playable

### Check Leaderboard

1. Navigate to `/coliseum-dashboard` or `/coliseum`
2. Verify 4 test artists appear in leaderboard
3. Rankings should match expected order:
   - Gamma (1st)
   - Alpha (2nd)
   - Delta (3rd)
   - Beta (4th)
4. Switch between domains (A/T/G/C) - rankings may differ
5. Switch between time ranges (7d/30d/alltime)

---

## 🔧 Troubleshooting

### Issue: No Artists Created

**Solution:**
```sql
-- Check if artists table exists
SELECT COUNT(*) FROM artist_profiles;

-- Check for errors
SELECT * FROM artist_profiles WHERE artist_name LIKE 'Test Artist%';
```

### Issue: No Content Created

**Solution:**
```sql
-- Check content_items table
SELECT COUNT(*) FROM content_items WHERE title LIKE '%Track%';

-- Verify artist IDs match
SELECT 
  ap.id as artist_id,
  ci.artist_id as content_artist_id
FROM artist_profiles ap
LEFT JOIN content_items ci ON ci.artist_id = ap.id
WHERE ap.artist_name LIKE 'Test Artist%';
```

### Issue: No Passport Events

**Solution:**
```sql
-- Check if users exist
SELECT COUNT(*) FROM auth.users;

-- Use existing users
SELECT id, email FROM auth.users LIMIT 2;
```

### Issue: Mutations Not Created

**Solution:**
1. Check processor logs for errors
2. Verify artist_id extraction:
   ```sql
   SELECT 
     entity_type,
     entity_id,
     metadata->>'artistId'
   FROM passport_entries
   WHERE coliseum_processed_at IS NULL
   LIMIT 5;
   ```
3. Redeploy processor if needed:
   ```bash
   supabase functions deploy coliseum-processor
   ```

### Issue: Rankings Don't Match Expected

**Possible Causes:**
1. Weights not applied correctly
2. Recency decay affecting older plays
3. Different time ranges showing different data

**Solution:**
```sql
-- Check weights applied
SELECT 
  ap.artist_name,
  COUNT(*) as play_count,
  ROUND(AVG(cm.weight), 2) as avg_weight,
  ROUND(SUM(cm.effective_delta), 2) as total_strength
FROM coliseum_dna_mutations cm
JOIN artist_profiles ap ON ap.id = cm.artist_id
WHERE ap.artist_name LIKE 'Test Artist%'
  AND cm.domain = 'T'
GROUP BY ap.id, ap.artist_name
ORDER BY total_strength DESC;
```

---

## 📊 Weight System Verification

The processor now implements tiered weighting:

- **TIER 1 (0.1x):** Low engagement (<30% completion)
- **TIER 2 (1.0x):** Standard play (30-80% completion)
- **TIER 3 (10.0x):** High engagement (>80% completion OR repeat play)

**Verify weights:**
```sql
-- Check weight distribution
SELECT 
  CASE 
    WHEN weight = 0.1 THEN 'TIER 1'
    WHEN weight = 1.0 THEN 'TIER 2'
    WHEN weight = 10.0 THEN 'TIER 3'
    ELSE 'Other'
  END as tier,
  COUNT(*) as count
FROM coliseum_dna_mutations
WHERE artist_id IN (
  SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
)
GROUP BY tier
ORDER BY tier;
```

---

## ✅ Success Criteria

Test data setup is successful when:

- [x] 4 test artists created
- [x] 16 tracks created (4 per artist)
- [x] 36 passport events created
- [x] Mutations created for all artists
- [x] Domain strength calculated
- [x] Leaderboard shows 4 artists
- [x] Rankings match expected order
- [x] Frontend displays artists in catalog
- [x] Frontend displays rankings correctly

---

## 🚀 Next Steps

After test data is set up:

1. **Verify Frontend:**
   - Check `/catalog` shows 4 artists
   - Check `/coliseum-dashboard` shows rankings

2. **Test Real Plays:**
   - Play tracks in frontend
   - Verify events logged to Passport
   - Trigger processor
   - Check rankings update

3. **Test Weight System:**
   - Play track to 90% completion (should get TIER 3 weight)
   - Play same track again (repeat play, should get TIER 3 weight)
   - Play track to 20% completion (should get TIER 1 weight)

4. **Monitor Processing:**
   - Check CRON runs every 5 minutes
   - Verify events processed automatically
   - Check leaderboard updates

---

**Status:** Ready to execute! 🎉
