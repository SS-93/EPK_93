# Coliseum Analytics - MVP Verification Checklist

**Date:** February 3, 2026  
**Status:** ✅ Ready for Final Verification  
**Project:** Buckets.MVP - Coliseum Analytics Engine

---

## 🎯 Verification Summary

Based on the Final Verification Summary document, the system is **100% ready for MVP deployment** with only CRON verification remaining.

---

## ✅ Pre-Verification Checklist

### Database Schema ✅
- [x] All 15 materialized views exist
- [x] All 7 core tables exist
- [x] `passport_entries.coliseum_processed_at` column exists
- [x] All analytics functions installed

### Frontend Code ✅
- [x] Track interface includes `artistId`
- [x] Passport event logging implemented
- [x] usePassport hook routes to Coliseum
- [x] Platform detection working

### Backend Infrastructure ✅
- [x] Coliseum processor Edge Function deployed
- [x] Passport API endpoint (`/api/passport/log`) operational
- [x] Treasury integration logging revenue events

---

## 🔍 Critical Verification Steps

### Step 1: Verify CRON Auto-Processing (5 min)

**Action Required:**
1. Go to Supabase Dashboard: https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/functions
2. Click on `coliseum-processor`
3. Navigate to **Settings** tab
4. Check **Cron Schedules** section
5. Verify schedule exists: `*/5 * * * *` (every 5 minutes)

**If CRON not configured:**
- Add new schedule: `*/5 * * * *`
- Save changes
- Wait 5 minutes and check logs

**Verification Query:**
```sql
-- Check if processor has run recently (within last 10 minutes)
SELECT 
  COUNT(*) as recent_events_processed
FROM passport_entries
WHERE coliseum_processed_at > NOW() - INTERVAL '10 minutes';
```

**Expected:** Count > 0 if CRON is working

---

### Step 2: Verify Event Schema Compatibility (CRITICAL)

**Issue Identified:** Processor expects `event.artist_id` but events may store artist ID in `metadata.artistId` or `entity_id`.

**Check Current Schema:**
```sql
-- Verify passport_entries structure
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'passport_entries'
ORDER BY ordinal_position;
```

**Check How Events Are Stored:**
```sql
-- Sample recent events
SELECT 
  id,
  event_type,
  entity_type,
  entity_id,
  metadata->>'artistId' as metadata_artist_id,
  metadata->>'artist_id' as metadata_artist_id_alt,
  coliseum_processed_at
FROM passport_entries
WHERE event_type IN ('player.track_played', 'treasury.money_spent')
ORDER BY created_at DESC
LIMIT 10;
```

**Expected Results:**
- If `entity_type = 'artist'` and `entity_id` is populated → ✅ Processor needs update
- If `metadata->>'artistId'` is populated → ✅ Processor needs update
- If both exist → Use `entity_id` first, fallback to `metadata.artistId`

**If Mismatch Found:**
See "Fix Required" section below.

---

### Step 3: Test End-to-End Pipeline (15 min)

#### 3.1 Create Test Event

**Option A: Via Frontend (Recommended)**
1. Start frontend: `npm start` (in frontend directory)
2. Login and play a track for 30+ seconds
3. Check browser console for: `✅ [usePassport] Event logged: player.track_played`

**Option B: Via API**
```bash
curl -X POST http://localhost:8000/api/passport/log \
  -H "Content-Type: application/json" \
  -d '{
    "type": "player.track_played",
    "userId": "YOUR_USER_ID",
    "artistId": "YOUR_ARTIST_ID",
    "trackId": "test-track-id",
    "at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
  }'
```

**Option C: Direct Database Insert**
```sql
INSERT INTO passport_entries (
  user_id,
  event_type,
  event_category,
  entity_type,
  entity_id,
  metadata,
  created_at
)
VALUES (
  (SELECT id FROM auth.users LIMIT 1),
  'player.track_played',
  'player',
  'artist',
  (SELECT id FROM artist_profiles LIMIT 1), -- artist_id as entity_id
  jsonb_build_object(
    'artistId', (SELECT id FROM artist_profiles LIMIT 1),
    'trackId', gen_random_uuid(),
    'trackTitle', 'Test Track',
    'source', 'web'
  ),
  NOW()
)
RETURNING id, event_type, entity_id, metadata->>'artistId';
```

#### 3.2 Verify Event Created
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

#### 3.3 Trigger Processor Manually
```bash
# Get your anon key from .env
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
ANON_KEY=$(grep SUPABASE_ANON_KEY .env | cut -d '=' -f2)

# Trigger processor
curl -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json"
```

**Expected Response:**
```json
{
  "success": true,
  "processed": 1,
  "mutations_generated": 4,
  "artists_recalculated": 1,
  "processing_time_ms": 1234
}
```

#### 3.4 Verify Mutations Created
```sql
SELECT 
  domain,
  key,
  delta,
  weight,
  recency_decay,
  effective_delta,
  occurred_at,
  created_at
FROM coliseum_dna_mutations
ORDER BY created_at DESC
LIMIT 10;
```

**Expected:** 4 mutations per event (A, T, G, C domains)

#### 3.5 Verify Domain Strength Updated
```sql
SELECT 
  ds.entity_id,
  ap.artist_name,
  ds.time_range,
  ds.a_strength,
  ds.t_strength,
  ds.g_strength,
  ds.c_strength,
  ds.calculated_at
FROM coliseum_domain_strength ds
LEFT JOIN artist_profiles ap ON ap.id = ds.entity_id
WHERE ds.entity_type = 'artist'
ORDER BY ds.calculated_at DESC
LIMIT 10;
```

**Expected:** Updated strength values for test artist

#### 3.6 Verify Leaderboard Views
```sql
-- Refresh views (if not auto-refreshed)
SELECT refresh_all_coliseum_leaderboards();

-- Check A-domain leaderboard
SELECT 
  artist_name,
  domain_strength,
  last_updated
FROM coliseum_leaderboard_a_7d
ORDER BY domain_strength DESC
LIMIT 10;
```

**Expected:** Test artist appears in leaderboard

---

## ⚠️ Potential Issues & Fixes

### Issue 1: Artist ID Extraction Mismatch

**Problem:** Processor expects `event.artist_id` but events store artist ID in `entity_id` or `metadata.artistId`.

**Fix Required:** Update processor to extract artist_id from multiple sources:

```typescript
// In coliseum-processor/index.ts, update generateMutations function:

function generateMutations(event: PassportEvent): DNAMutation[] {
  const mutations: DNAMutation[] = [];
  const baseWeight = getEventWeight(event.event_type);
  const recencyDecay = calculateRecencyDecay(event.timestamp, event.event_type);
  const metadata = event.metadata || {};
  
  // Extract artist_id from multiple sources
  const artistId = 
    event.artist_id ||  // Direct field (if exists)
    (event.entity_type === 'artist' ? event.entity_id : null) ||  // Entity ID
    metadata.artistId ||  // Metadata field
    metadata.artist_id;   // Alternative metadata field
  
  if (!artistId) {
    console.warn(`[Coliseum] Skipping event ${event.id}: No artist_id found`);
    return []; // Return empty if no artist
  }
  
  // Use artistId in all mutations
  mutations.push({
    passport_entry_id: event.id,
    user_id: event.user_id,
    artist_id: artistId,  // Use extracted artistId
    // ... rest of mutation
  });
  
  return mutations;
}
```

**Also update affected artists collection:**
```typescript
// In main processor loop (around line 329):
const affectedArtists = new Set<string>();
for (const event of events) {
  const artistId = 
    event.artist_id ||
    (event.entity_type === 'artist' ? event.entity_id : null) ||
    event.metadata?.artistId ||
    event.metadata?.artist_id;
  
  if (artistId) {
    affectedArtists.add(artistId);
  }
}
```

---

### Issue 2: Timestamp Column Name

**Problem:** Processor uses `event.timestamp` but table may use `created_at`.

**Check:**
```sql
SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'passport_entries' 
  AND column_name IN ('timestamp', 'created_at');
```

**Fix:** Update processor to use correct column name:
```typescript
// Use created_at if timestamp doesn't exist
const eventTimestamp = event.timestamp || event.created_at;
```

---

### Issue 3: Missing RPC Function

**Problem:** `refresh_coliseum_leaderboards` function may not exist.

**Check:**
```sql
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name LIKE '%coliseum%' 
  AND routine_schema = 'public';
```

**Fix:** Create function if missing (see migration files).

---

## 📊 Success Criteria

**MVP is ready when:**

- [x] All database tables/views exist
- [x] Processor Edge Function deployed
- [x] Frontend logging events
- [ ] CRON auto-processing verified
- [ ] End-to-end test passes
- [ ] Mutations created successfully
- [ ] Domain strength calculated
- [ ] Leaderboard views populated

---

## 🚀 Quick Verification Script

Run this complete verification:

```bash
#!/bin/bash
# coliseum_verification.sh

echo "🔍 Coliseum MVP Verification"
echo "============================"

# 1. Check database tables
echo "1. Checking database tables..."
psql $DATABASE_URL -c "
SELECT 
  CASE WHEN COUNT(*) = 7 THEN '✅ Core tables exist' 
       ELSE '❌ Missing tables' END as status
FROM information_schema.tables 
WHERE table_name IN (
  'coliseum_domain_strength',
  'coliseum_dna_mutations',
  'coliseum_entitlements',
  'coliseum_leaderboards',
  'coliseum_metrics',
  'coliseum_reports',
  'coliseum_rollups'
);
"

# 2. Check views
echo "2. Checking materialized views..."
psql $DATABASE_URL -c "
SELECT 
  CASE WHEN COUNT(*) = 15 THEN '✅ All views exist' 
       ELSE '❌ Missing views' END as status
FROM pg_matviews 
WHERE matviewname LIKE 'coliseum_leaderboard%';
"

# 3. Check processor function
echo "3. Checking processor function..."
curl -s -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  | jq -r '.success // "❌ Processor error"'

# 4. Check unprocessed events
echo "4. Checking unprocessed events..."
psql $DATABASE_URL -c "
SELECT 
  COUNT(*) as unprocessed_count,
  CASE WHEN COUNT(*) > 0 THEN '⚠️ Events pending' 
       ELSE '✅ All processed' END as status
FROM passport_entries
WHERE coliseum_processed_at IS NULL
  AND event_type IN ('player.track_played', 'treasury.money_spent');
"

echo "============================"
echo "✅ Verification complete!"
```

---

## 📝 Next Steps After Verification

1. **If all checks pass:** ✅ System ready for production
2. **If issues found:** Fix using sections above, then re-verify
3. **Monitor first 24 hours:** Check processor logs, verify CRON runs
4. **Create monitoring dashboard:** Track processing metrics

---

## 📚 Reference Documents

- **Full Review**: `COLISEUM_ANALYTICS_REVIEW.md`
- **Next Steps**: `COLISEUM_NEXT_STEPS.md`
- **Implementation Plan**: `/Users/pks.ml/Desktop/93/my-app/SystemFunctionality_ImplementationPlan_Buckets_MVP.md`
- **Final Verification**: (The document you provided)

---

**Last Updated:** February 3, 2026  
**Status:** Ready for Verification ✅
