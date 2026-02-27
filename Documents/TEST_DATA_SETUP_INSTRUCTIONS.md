# Test Data Setup Instructions

**Purpose:** Set up test data with audio files for Coliseum testing  
**Time:** ~10 minutes

---

## 🎯 Quick Setup

### Option 1: Automated Script (Recommended)

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB

# Set DATABASE_URL (required for SQL scripts)
# Format: postgresql://postgres:[PASSWORD]@[HOST]:[PORT]/postgres
export DATABASE_URL="postgresql://postgres:[YOUR_PASSWORD]@db.iutnwgvzwyupsuguxnls.supabase.co:5432/postgres"

# Run complete setup
./scripts/complete_test_setup.sh
```

This will:
1. ✅ Create 4 test artists
2. ✅ Create 16 test tracks (4 per artist)
3. ✅ Upload 4 audio files from `/Users/pks.ml/Desktop/93/my-app/Test-Audio/`
4. ✅ Assign audio files to artists (one per artist)
5. ✅ Simulate 36 audio plays
6. ✅ Trigger Coliseum processor
7. ✅ Verify results and show leaderboard

### Option 2: Step-by-Step Manual

#### Step 1: Create Test Artists & Content

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
export DATABASE_URL="postgresql://..."

psql "$DATABASE_URL" -f scripts/create_coliseum_test_data.sql
```

#### Step 2: Upload Audio Files

```bash
node scripts/upload_test_audio_files.js
```

**This will:**
- Find test artists in database
- Upload 4 audio files from frontend Test-Audio directory
- Assign one file per artist (round-robin)
- Update content_items with file URLs

#### Step 3: Simulate Plays

```bash
psql "$DATABASE_URL" -f scripts/simulate_audio_plays.sql
```

#### Step 4: Trigger Processor

```bash
SERVICE_KEY=$(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d '=' -f2 | tr -d '"')

curl -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json"
```

---

## 📁 Audio Files Location

**Source:** `/Users/pks.ml/Desktop/93/my-app/Test-Audio/`

**Files:**
1. `akuma-new-jazz-type-beat_TK16053830.mp3.mp3` → Test Artist Delta (Jazz)
2. `free-selfish-acoustic-sza-x-her-type-beat_TK14845480.mp3.mp3` → Test Artist Beta (Indie)
3. `free-soul-acoustic-sza-x-jhene-aiko-type-beat_TK15547357.mp3.mp3` → Test Artist Gamma (Hip-Hop)
4. `free-timing-acoustic-sza-x-her-type-beat_TK14920459.mp3.mp3` → Test Artist Alpha (Electronic)

**Assignment:** Round-robin (one file per artist, cycling through artists)

---

## 🔍 Verification

### Check Artists Created

```sql
SELECT artist_name, COUNT(ci.id) as track_count
FROM artist_profiles ap
LEFT JOIN content_items ci ON ci.artist_id = ap.id
WHERE ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name;
```

**Expected:** 4 artists, 16 tracks total

### Check Audio Files Uploaded

```sql
SELECT 
  ap.artist_name,
  ci.title,
  ci.file_path,
  CASE WHEN ci.file_path LIKE 'http%' THEN '✅ Uploaded' ELSE '❌ Missing' END as status
FROM artist_profiles ap
JOIN content_items ci ON ci.artist_id = ap.id
WHERE ap.artist_name LIKE 'Test Artist%'
  AND ci.title LIKE '%Track 1%'
ORDER BY ap.artist_name;
```

**Expected:** All Track 1 items have file_path URLs

### Check Storage Bucket

Go to Supabase Dashboard → Storage → Check `audio` bucket (or `content`/`tracks`)

**Expected:** Files in `test-artists/{artist-name}/` folders

---

## 🎨 Frontend Verification

### Catalog Page

1. Start frontend: `cd /Users/pks.ml/Desktop/93/my-app && npm start`
2. Navigate to: `http://localhost:3000/catalog`
3. Verify:
   - ✅ 4 test artists visible
   - ✅ Each artist has tracks
   - ✅ Tracks are playable (audio files work)

### Coliseum Dashboard

1. Navigate to: `http://localhost:3000/coliseum-dashboard`
2. Verify:
   - ✅ 4 test artists in leaderboard
   - ✅ Rankings match expected order
   - ✅ Strength values displayed

---

## 🧪 E2E Test Preparation

After test data is set up:

1. **Run E2E Tests:**
   ```bash
   cd /Users/pks.ml/Desktop/93/my-app
   npx playwright test tests/e2e/full-audio-flow.spec.ts --ui
   ```

2. **E2E Test Will:**
   - Create its own test user/artist/track
   - Use test harness at `/test-passport`
   - Verify complete flow
   - Clean up its own data

3. **Note:** E2E test data is separate from SQL test data

---

## 🐛 Troubleshooting

### Issue: DATABASE_URL Not Set

**Solution:**
```bash
# Get connection string from Supabase Dashboard
# Settings → Database → Connection String
export DATABASE_URL="postgresql://postgres:[PASSWORD]@db.iutnwgvzwyupsuguxnls.supabase.co:5432/postgres"
```

### Issue: Storage Bucket Not Found

**Solution:**
1. Check Supabase Dashboard → Storage
2. Verify bucket name (common: `audio`, `content`, `tracks`)
3. Update `STORAGE_BUCKET` in `upload_test_audio_files.js`

### Issue: Audio Files Not Uploading

**Check:**
1. Files exist in `/Users/pks.ml/Desktop/93/my-app/Test-Audio/`
2. Service role key is correct
3. Storage bucket exists and is accessible
4. File permissions allow reading

### Issue: Content Items Not Updated

**Check:**
1. Artists exist in database
2. Content items exist for artists
3. File URLs are valid
4. Database update permissions

---

## ✅ Success Criteria

Test data setup is successful when:

- [x] 4 test artists created
- [x] 16 tracks created (4 per artist)
- [x] 4 audio files uploaded to storage
- [x] Content items have file_path/file_url set
- [x] 36 passport events created
- [x] Mutations created for all artists
- [x] Domain strength calculated
- [x] Leaderboard shows rankings
- [x] Frontend catalog shows artists
- [x] Frontend leaderboard shows rankings
- [x] Audio files playable in frontend

---

**Status:** Ready to execute! 🚀
