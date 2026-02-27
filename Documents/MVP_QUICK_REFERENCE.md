# Buckets.MVP - Quick Reference Card

## ✅ MVP Status: OPERATIONAL

**Last Verified:** February 3, 2026
**System Health:** 🟢 All systems go

---

## 🚀 Run Integration Test

```bash
cd /Users/pks.ml/Desktop/93/my-app
node tests/coliseum-integration-test.js
```

**Expected:** ✅ PASSED (6 mutations, 3 domain strength records)

---

## 🎯 What's Working

| System | Status | Notes |
|--------|--------|-------|
| Passport Events | 🟢 | Capturing user interactions |
| Coliseum Processor | 🟢 | Generating DNA mutations |
| Domain Strength | 🟢 | A/T/G/C calculations |
| Leaderboards | 🟢 | Rankings updating |
| Pipeline | 🟢 | Event → Mutation → Rank |

---

## ⚙️ TODO: Enable CRON (5 min)

1. Go to: https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/functions
2. Click `coliseum-processor` → Settings
3. Add schedule: `*/5 * * * *`
4. Save

---

## 🎯 Next Priorities

### 1. Stripe Production Integration
- [ ] Update API keys (test → live)
- [ ] Configure production webhooks
- [ ] Test real payment flow
- [ ] Monitor first transactions

### 2. Treasury Architecture
- [ ] Design payout calculation
- [ ] Artist earnings tracking
- [ ] Revenue distribution logic
- [ ] Payment scheduling system

### 3. Analytics Viewer Access
- [ ] Dashboard for data analyzers
- [ ] View: Artists, songs, plays
- [ ] Read-only permissions
- [ ] Data export capability

---

## 🔍 Quick Diagnostics

### Check System Health
```sql
-- Unprocessed events
SELECT COUNT(*) FROM passport_entries
WHERE coliseum_processed_at IS NULL;

-- Recent mutations
SELECT COUNT(*), domain FROM coliseum_dna_mutations
WHERE processed_at > NOW() - INTERVAL '1 hour'
GROUP BY domain;

-- Top artists
SELECT * FROM coliseum_leaderboard_t_7d
ORDER BY domain_strength DESC LIMIT 10;
```

### Trigger Processor Manually
```bash
curl -X POST \
  https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```

---

## 🎓 Key Lessons

1. **Test at the right level** - Integration > E2E for backend
2. **Clear the queue** - Check for event backlogs
3. **Verify schema first** - Don't assume database structure
4. **Check actual outcomes** - Query DB, don't just trust API responses

---

## 📞 Emergency Contacts

- **Supabase Dashboard:** https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls
- **Full Protocol:** `Documents/BUCKETS_MVP_TEST_PROTOCOL.md`
- **Test Script:** `tests/coliseum-integration-test.js`

---

**🎉 MVP ACHIEVED! Ready for production traffic. 🎉**
