# Coliseum Analytics - MVP Completion Guide

**Date:** February 3, 2026  
**Status:** 🟢 Ready for Final Verification  
**Estimated Time:** ~30 minutes

---

## 🎯 Success Criteria Checklist

- [x] ✅ Database migrations applied
- [x] ✅ Frontend logs audio plays to Passport
- [ ] ⏳ CRON processor runs every 5 minutes (verify)
- [ ] ⏳ Manual processor trigger works (test)
- [ ] ⏳ Mutations created for events (test)
- [ ] ⏳ Domain strength calculated (test)
- [ ] ⏳ Leaderboard views populated (test)
- [ ] ⏳ Frontend dashboard displays rankings (test)

---

## 📋 Step-by-Step Verification

### Step 1: Verify CRON Auto-Processing (5 minutes)

#### 1.1 Check Supabase Dashboard

1. Navigate to: https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/functions
2. Click on `coliseum-processor`
3. Go to **Settings** tab
4. Scroll to **Cron Schedules** section

#### 1.2 Verify or Configure CRON

**If CRON exists:**
- ✅ Verify schedule: `*/5 * * * *` (every 5 minutes)
- ✅ Status: Active/Enabled
- ✅ Note the last run time

**If CRON doesn't exist:**
- Click **Add Schedule**
- Schedule: `*/5 * * * *`
- Method: POST
- Headers: `{"Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}`
- Body: `{}`
- Save

#### 1.3 Verify Recent Processing

```sql
-- Check if processor has run in last 10 minutes
SELECT 
  COUNT(*) as events_processed_recently,
  MAX(coliseum_processed_at) as last_processed_time
FROM passport_entries
WHERE coliseum_processed_at > NOW() - INTERVAL '10 minutes';
```

**Expected:** Count > 0 if CRON is working

**If count is 0:**
- Wait 5 minutes and check again
- Or proceed to manual trigger test (Step 2)

---

### Step 2: Test Manual Processor Trigger (5 minutes)

#### 2.1 Get Required Credentials

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB

# Get anon key
ANON_KEY=$(grep SUPABASE_ANON_KEY .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")

# Or get service role key (more reliable)
SERVICE_KEY=$(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")

echo "Using key: ${SERVICE_KEY:0:20}..."
```

#### 2.2 Trigger Processor Manually

```bash
curl -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' \
  -v
```

#### 2.3 Verify Response

**Expected Success Response:**
```json
{
  "success": true,
  "processed": 5,
  "mutations_generated": 20,
  "artists_recalculated": 3,
  "processing_time_ms": 1234
}
```

**If Error:**
- Check error message
- Verify service role key is correct
- Check Supabase function logs

**If processed: 0:**
- No unprocessed events (this is OK if system is caught up)
- Proceed to create test event (Step 3)

---

### Step 3: Create Test Event (5 minutes)

#### 3.1 Check for Existing Unprocessed Events

```sql
SELECT 
  COUNT(*) as unprocessed_count,
  event_type,
  COUNT(*) FILTER (WHERE entity_type = 'artist') as artist_events
FROM passport_entries
WHERE coliseum_processed_at IS NULL
GROUP BY event_type
ORDER BY unprocessed_count DESC;
```

**If count > 0:** Skip to Step 4 (test mutations)

**If count = 0:** Create test event below

#### 3.2 Create Test Event via SQL

```sql
-- Get test user and artist IDs
WITH test_data AS (
  SELECT 
    (SELECT id FROM auth.users LIMIT 1) as user_id,
    (SELECT id FROM artist_profiles LIMIT 1) as artist_id
)
INSERT INTO passport_entries (
  user_id,
  event_type,
  event_category,
  entity_type,
  entity_id,
  metadata,
  created_at
)
SELECT 
  user_id,
  'player.track_played',
  'player',
  'artist',
  artist_id,
  jsonb_build_object(
    'artistId', artist_id,
    'trackId', gen_random_uuid(),
    'trackTitle', 'Test Track for Coliseum',
    'source', 'web',
    'duration_seconds', 180,
    'total_duration_seconds', 180
  ),
  NOW()
FROM test_data
RETURNING id, event_type, entity_id, metadata->>'artistId';
```

#### 3.3 Verify Event Created

```sql
SELECT 
  id,
  event_type,
  entity_type,
  entity_id,
  metadata->>'artistId' as metadata_artist_id,
  coliseum_processed_at,
  created_at
FROM passport_entries
WHERE event_type = 'player.track_played'
  AND coliseum_processed_at IS NULL
ORDER BY created_at DESC
LIMIT 5;
```

**Expected:** At least 1 row with `coliseum_processed_at IS NULL`

---

### Step 4: Verify Mutations Created (5 minutes)

#### 4.1 Trigger Processor

Use the manual trigger from Step 2, or wait for CRON.

#### 4.2 Check Mutations Table

```sql
SELECT 
  domain,
  key,
  COUNT(*) as mutation_count,
  ROUND(SUM(effective_delta), 2) as total_strength,
  MIN(occurred_at) as first_mutation,
  MAX(occurred_at) as last_mutation
FROM coliseum_dna_mutations
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY domain, key
ORDER BY domain, total_strength DESC;
```

**Expected Results:**
- **A-domain:** Genre mutations (if artist_genres in metadata)
- **T-domain:** `engagement` mutations (always created)
- **G-domain:** `revenue` mutations (if purchase events)
- **C-domain:** `city:*` mutations (if location data)

**Minimum Expected:** At least T-domain mutations (engagement)

#### 4.3 Verify Artist ID Extraction

```sql
SELECT 
  artist_id,
  COUNT(*) as mutation_count,
  COUNT(DISTINCT domain) as domains_count
FROM coliseum_dna_mutations
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY artist_id
HAVING COUNT(*) > 0
ORDER BY mutation_count DESC;
```

**Expected:** All mutations have non-null `artist_id`

**If artist_id is NULL:**
- ⚠️ Processor fix may not be deployed
- Redeploy: `supabase functions deploy coliseum-processor`

---

### Step 5: Verify Domain Strength Calculated (5 minutes)

#### 5.1 Check Domain Strength Table

```sql
SELECT 
  ds.entity_id,
  ap.artist_name,
  ds.time_range,
  ROUND(ds.a_strength, 2) as a_strength,
  ROUND(ds.t_strength, 2) as t_strength,
  ROUND(ds.g_strength, 2) as g_strength,
  ROUND(ds.c_strength, 2) as c_strength,
  ds.calculated_at
FROM coliseum_domain_strength ds
LEFT JOIN artist_profiles ap ON ap.id = ds.entity_id
WHERE ds.entity_type = 'artist'
  AND ds.calculated_at > NOW() - INTERVAL '1 hour'
ORDER BY ds.calculated_at DESC
LIMIT 10;
```

**Expected:**
- Rows for each artist with recent events
- Non-zero strength values (at least T-domain)
- `calculated_at` timestamp within last hour

#### 5.2 Verify All Time Ranges

```sql
SELECT 
  entity_id,
  COUNT(*) as time_range_count,
  ARRAY_AGG(time_range) as time_ranges
FROM coliseum_domain_strength
WHERE entity_type = 'artist'
  AND calculated_at > NOW() - INTERVAL '1 hour'
GROUP BY entity_id
HAVING COUNT(*) < 3;
```

**Expected:** Empty result (all artists should have 3 time ranges: 7d, 30d, alltime)

**If rows returned:** Some artists missing time ranges (processor may have timed out)

---

### Step 6: Verify Leaderboard Views (5 minutes)

#### 6.1 Check View Existence

```sql
SELECT 
  matviewname,
  pg_size_pretty(pg_total_relation_size(('public.' || matviewname)::regclass)) as size,
  (SELECT COUNT(*) FROM pg_stat_user_tables WHERE relname = matviewname) as exists
FROM pg_matviews
WHERE matviewname LIKE 'coliseum_leaderboard%'
ORDER BY matviewname;
```

**Expected:** 15 views listed

#### 6.2 Refresh Views (if needed)

```sql
-- Refresh all leaderboard views
SELECT refresh_all_coliseum_leaderboards();

-- Or refresh individually
REFRESH MATERIALIZED VIEW CONCURRENTLY coliseum_leaderboard_a_7d;
REFRESH MATERIALIZED VIEW CONCURRENTLY coliseum_leaderboard_t_7d;
REFRESH MATERIALIZED VIEW CONCURRENTLY coliseum_leaderboard_g_7d;
REFRESH MATERIALIZED VIEW CONCURRENTLY coliseum_leaderboard_c_7d;
REFRESH MATERIALIZED VIEW CONCURRENTLY coliseum_leaderboard_composite_7d;
```

#### 6.3 Query Leaderboard Data

```sql
-- A-domain leaderboard (7d)
SELECT 
  artist_name,
  ROUND(domain_strength, 2) as strength,
  last_updated
FROM coliseum_leaderboard_a_7d
ORDER BY domain_strength DESC
LIMIT 10;

-- Composite leaderboard (7d)
SELECT 
  artist_name,
  ROUND(domain_strength, 2) as strength,
  last_updated
FROM coliseum_leaderboard_composite_7d
ORDER BY domain_strength DESC
LIMIT 10;
```

**Expected:** Artists ranked by strength, with non-zero values

**If empty:**
- Check if views need refresh
- Verify domain_strength table has data
- Check view definition matches table structure

---

### Step 7: Test Frontend Dashboard (5 minutes)

#### 7.1 Start Frontend (if not running)

```bash
# Navigate to frontend directory
cd /Users/pks.ml/Desktop/93/my-app  # Adjust path as needed

# Start dev server
npm start
```

#### 7.2 Navigate to Coliseum Dashboard

1. Open browser: http://localhost:3000
2. Login with test account
3. Navigate to: `/coliseum-dashboard` or `/coliseum`

#### 7.3 Verify Dashboard Displays

**Expected UI Elements:**
- ✅ Leaderboard table/list
- ✅ Domain selector (A/T/G/C/Composite)
- ✅ Time range selector (7d/30d/alltime)
- ✅ Artist rankings
- ✅ Strength values displayed

**Expected Data:**
- ✅ Artists from test data appear
- ✅ Rankings match database queries
- ✅ Switching domains shows different rankings
- ✅ No console errors

#### 7.4 Check Browser Console

Open DevTools → Console

**Expected Logs:**
- ✅ No errors
- ✅ API calls successful (200 status)
- ✅ Data loaded successfully

**If Errors:**
- Check API endpoint URLs
- Verify authentication tokens
- Check network tab for failed requests

---

## 🐛 Troubleshooting Guide

### Issue: CRON Not Running

**Symptoms:**
- No events processed in last 10 minutes
- `coliseum_processed_at` remains NULL

**Solutions:**
1. Verify CRON schedule in Supabase Dashboard
2. Check function logs for errors
3. Test manual trigger first
4. Verify service role key is correct

### Issue: No Mutations Created

**Symptoms:**
- Processor runs successfully
- `processed: X` but `mutations_generated: 0`

**Solutions:**
1. Check if events have `artist_id`:
   ```sql
   SELECT 
     entity_type,
     entity_id,
     metadata->>'artistId'
   FROM passport_entries
   WHERE coliseum_processed_at IS NULL
   LIMIT 5;
   ```
2. Verify processor fix is deployed
3. Check processor logs for warnings

### Issue: Domain Strength Not Updating

**Symptoms:**
- Mutations created
- Domain strength values unchanged

**Solutions:**
1. Check `recalculateDomainStrength` function logs
2. Verify mutations have correct `artist_id`
3. Check time range calculations
4. Verify `coliseum_domain_strength` table exists

### Issue: Leaderboard Views Empty

**Symptoms:**
- Views exist but return no rows
- Domain strength table has data

**Solutions:**
1. Refresh views manually
2. Check view definition:
   ```sql
   SELECT pg_get_viewdef('coliseum_leaderboard_a_7d', true);
   ```
3. Verify view joins artist_profiles correctly
4. Check if artist_profiles table has matching IDs

### Issue: Frontend Not Loading Data

**Symptoms:**
- Dashboard loads but shows no artists
- Console shows API errors

**Solutions:**
1. Check API endpoint URL
2. Verify authentication token
3. Check CORS settings
4. Verify API route exists: `/api/coliseum/leaderboard`
5. Test API directly:
   ```bash
   curl http://localhost:8000/api/coliseum/leaderboard?domain=A&time_range=7d
   ```

---

## ✅ Completion Checklist

After completing all steps, verify:

- [ ] CRON schedule verified and active
- [ ] Manual trigger returns success
- [ ] Test event created successfully
- [ ] Mutations created with artist_id
- [ ] Domain strength calculated for all time ranges
- [ ] Leaderboard views populated
- [ ] Frontend dashboard displays rankings
- [ ] No console errors
- [ ] All SQL queries return expected results

---

## 📊 Quick Verification Script

Run this complete verification:

```bash
#!/bin/bash
# coliseum_mvp_verification.sh

echo "🔍 Coliseum MVP Verification"
echo "============================"

# Load environment variables
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
source .env 2>/dev/null || true

# 1. Check unprocessed events
echo "1. Checking unprocessed events..."
UNPROCESSED=$(psql "$DATABASE_URL" -t -c "
  SELECT COUNT(*) FROM passport_entries 
  WHERE coliseum_processed_at IS NULL 
  AND event_type IN ('player.track_played', 'treasury.money_spent');
" | xargs)
echo "   Unprocessed events: $UNPROCESSED"

# 2. Check mutations
echo "2. Checking recent mutations..."
MUTATIONS=$(psql "$DATABASE_URL" -t -c "
  SELECT COUNT(*) FROM coliseum_dna_mutations 
  WHERE created_at > NOW() - INTERVAL '1 hour';
" | xargs)
echo "   Mutations created (last hour): $MUTATIONS"

# 3. Check domain strength
echo "3. Checking domain strength..."
STRENGTH=$(psql "$DATABASE_URL" -t -c "
  SELECT COUNT(*) FROM coliseum_domain_strength 
  WHERE calculated_at > NOW() - INTERVAL '1 hour';
" | xargs)
echo "   Domain strength records (last hour): $STRENGTH"

# 4. Test processor
echo "4. Testing processor..."
RESPONSE=$(curl -s -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json")
SUCCESS=$(echo $RESPONSE | jq -r '.success // false')
PROCESSED=$(echo $RESPONSE | jq -r '.processed // 0')
echo "   Processor success: $SUCCESS"
echo "   Events processed: $PROCESSED"

# 5. Check leaderboard views
echo "5. Checking leaderboard views..."
VIEW_COUNT=$(psql "$DATABASE_URL" -t -c "
  SELECT COUNT(*) FROM pg_matviews 
  WHERE matviewname LIKE 'coliseum_leaderboard%';
" | xargs)
echo "   Leaderboard views: $VIEW_COUNT"

echo "============================"
if [ "$SUCCESS" = "true" ] && [ "$MUTATIONS" -gt 0 ]; then
  echo "✅ MVP Verification: PASSED"
else
  echo "⚠️ MVP Verification: NEEDS ATTENTION"
fi
```

---

## 📝 Final Status Report Template

After completing verification, document results:

```markdown
# Coliseum MVP Verification Report

**Date:** [Date]
**Verified By:** [Name]

## Results

### CRON Verification
- Status: ✅ Active / ⏳ Not Configured
- Schedule: `*/5 * * * *`
- Last Run: [Timestamp]

### Manual Trigger
- Status: ✅ Success / ❌ Failed
- Response: [JSON response]
- Processing Time: [ms]

### Mutations
- Created: [Count]
- Domains: A/T/G/C
- Artist IDs: All present ✅

### Domain Strength
- Artists Updated: [Count]
- Time Ranges: 7d/30d/alltime ✅
- Values: Non-zero ✅

### Leaderboards
- Views: 15/15 ✅
- Data: Populated ✅
- Rankings: Correct ✅

### Frontend
- Dashboard: ✅ Loads
- Data Display: ✅ Correct
- Errors: None ✅

## Issues Found
[List any issues]

## Recommendations
[List recommendations]

## Status
✅ MVP READY / ⏳ NEEDS FIXES
```

---

**Estimated Completion Time:** 30 minutes  
**Status:** Ready to verify! 🚀
