# Coliseum MVP - Quick Verification (30 min)

## 🚀 Fast Track Checklist

### 1. Verify CRON (5 min)
```bash
# Check Supabase Dashboard
https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/functions
→ coliseum-processor → Settings → Cron Schedules
→ Verify: */5 * * * *
```

### 2. Test Manual Trigger (5 min)
```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
SERVICE_KEY=$(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d '=' -f2 | tr -d '"')

curl -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json"
```

**Expected:** `{"success": true, "processed": X, ...}`

### 3. Check Mutations (5 min)
```sql
SELECT 
  domain,
  COUNT(*) as count,
  COUNT(DISTINCT artist_id) as artists
FROM coliseum_dna_mutations
WHERE created_at > NOW() - INTERVAL '1 hour'
GROUP BY domain;
```

**Expected:** Rows for A/T/G/C domains

### 4. Check Domain Strength (5 min)
```sql
SELECT 
  entity_id,
  time_range,
  a_strength,
  t_strength,
  g_strength,
  c_strength
FROM coliseum_domain_strength
WHERE calculated_at > NOW() - INTERVAL '1 hour'
LIMIT 5;
```

**Expected:** Non-zero strength values

### 5. Check Leaderboards (5 min)
```sql
SELECT artist_name, domain_strength
FROM coliseum_leaderboard_a_7d
ORDER BY domain_strength DESC
LIMIT 10;
```

**Expected:** Artists ranked by strength

### 6. Test Frontend (5 min)
```bash
# Start frontend
npm start

# Navigate to: http://localhost:3000/coliseum-dashboard
```

**Expected:** Leaderboard displays with rankings

---

## ✅ Success = All Steps Pass

**If any step fails:** See `COLISEUM_MVP_COMPLETION_GUIDE.md` for detailed troubleshooting.

---

## 🎯 Quick SQL Verification

Run this single query to check everything:

```sql
WITH checks AS (
  SELECT 
    (SELECT COUNT(*) FROM passport_entries WHERE coliseum_processed_at IS NULL) as unprocessed,
    (SELECT COUNT(*) FROM coliseum_dna_mutations WHERE created_at > NOW() - INTERVAL '1 hour') as mutations,
    (SELECT COUNT(*) FROM coliseum_domain_strength WHERE calculated_at > NOW() - INTERVAL '1 hour') as strength,
    (SELECT COUNT(*) FROM coliseum_leaderboard_a_7d) as leaderboard_rows
)
SELECT 
  CASE WHEN unprocessed = 0 THEN '✅' ELSE '⏳' END || ' Unprocessed: ' || unprocessed as status_1,
  CASE WHEN mutations > 0 THEN '✅' ELSE '❌' END || ' Mutations: ' || mutations as status_2,
  CASE WHEN strength > 0 THEN '✅' ELSE '❌' END || ' Strength: ' || strength as status_3,
  CASE WHEN leaderboard_rows > 0 THEN '✅' ELSE '❌' END || ' Leaderboard: ' || leaderboard_rows as status_4
FROM checks;
```

---

**Time:** ~30 minutes  
**Status:** Ready! 🚀
