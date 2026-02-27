# Session Summary: Treasury Test Page & Split Engine
**Date:** February 16, 2026  
**Focus:** Treasury test infrastructure, revenue split engine, artist account linking

---

## What Was Built

### 1. Treasury Test Page (`test-treasury.tsx`)
Complete rewrite of the test treasury page with 4 tabbed sections:

| Tab | Function |
|-----|----------|
| **💰 Add Funds** | Credit user wallets with test funds ($10–$500 presets) |
| **🎪 Event & Splits** | Connect to events, link artists, apply revenue splits |
| **👤 User Status** | Badge inspector for all 3 test accounts |
| **📋 Logs** | Passport + ledger entries with category breakdown |

### 2. Backend Endpoints Added to `server.js`

| Endpoint | Purpose |
|----------|---------|
| `POST /api/treasury/add-funds` | Single credit entry for test funding (skips platform debit — FK constraint) |
| `POST /api/treasury/connect-event` | Load event details, host, artists, split rules |
| `POST /api/treasury/connect-artist` | Link artist badge users to events via `event_artist_prospects` |
| `POST /api/treasury/apply-splits` | Mock purchase → full split engine distribution |
| `GET /api/treasury/user-status/:userId` | Badges, balance, host/artist status |
| `GET /api/treasury/logs/:userId` | Passport + ledger entries |

### 3. Artist Registration – Link Account (`ArtistRegistration.tsx`)
Added **🔗 Link Account** to the concierto artist registration page:
- **Not signed in** → "Sign In to Link" redirects to `/login` with return URL
- **Signed in** → "Link Account" writes `migrated_to_user_id` to `event_artist_prospects`
- **Already linked** → Green "Account Linked" confirmation
- Appears on both the registration form and completion screens

---

## Split Engine Architecture

The `applyRevenueSplits()` function (line ~1570 in server.js) runs the full distribution:

```
Purchase → Split Rules → Multi-Artist Distribution → Ledger Credits → Passport Logging
```

**Flow:**
1. Load split rules from `split_rules` table (event-specific → default → hardcoded 70/20/10)
2. Find confirmed artists via `event_artist_prospects.migrated_to_user_id`
3. Divide artist share equally among all confirmed artists
4. Credit host from `events.host_user_id`
5. Process profit share partners from `event_profit_share_partners`
6. Create `ledger_entries` (credits) for each recipient
7. Log to Passport: `revenue.split_applied` + per-artist `treasury.revenue_split_applied`

**Default Split Rules (70/20/10):**

| Role | % | Distribution |
|------|---|-------------|
| 🎤 Artists | 70% | Split equally among confirmed artists |
| 🏗️ Platform | 20% | Held (no ledger entry yet — future platform view) |
| 🏠 Host | 10% | Credited to event host |

**Verified Example ($5,000 purchase, 2 artists):**
- Artist I: $1,750 (35%)
- Artist II: $1,750 (35%)
- Host: $500 (10%)
- Platform: $1,000 (20%) — held

---

## Bugs Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| RLS 403 on ledger inserts | Frontend using anon key | Backend uses service_role key, bypassing RLS |
| `PLATFORM_RESERVE_ID` FK violation | `00000000-...` doesn't exist in `users` table | Switched to single credit entry (no platform debit) |
| `fulfillment_status: 'test'` rejected | DB check constraint only allows `pending`/`fulfilled` | Changed to `'pending'` |
| Passport 400 on insert | `event_data` column doesn't exist; uses `metadata` | Fixed `logPassportEvent` to use `metadata` column |
| Passport `valid_event_category` constraint | `'financial'` not in allowed categories | Changed all to `'interaction'` (8 instances) |
| `TEST_ACCOUNTS.filter` crash | `TEST_ACCOUNTS` is an object, not array | Used `Object.values(TEST_ACCOUNTS).filter()` |
| 0 confirmed artists in splits | No `event_artist_prospects` rows existed | Added connect-artist endpoint + frontend UI |

---

## Test Accounts

| Label | User ID | Role |
|-------|---------|------|
| Host (Test-3) | `63dd0fbb-172c-47c2-b0c7-4a1582a93d7e` | Host of event "2k26" |
| Artist I | `23e4399e-b504-42ca-a9f6-71ac4ca1300c` | Connected artist |
| Artist II | `cae86905-fbcf-44fe-ac6f-7b1aae30e5f1` | Connected artist |

**Event:** "2k26" — ID `488a252a-1ed1-4369-b79b-ec55f1a51566`

---

## Files Modified

| File | Changes |
|------|---------|
| `Buckets_SB/server.js` | 6 new endpoints, fixed `logPassportEvent`, fixed `event_category`, fixed `fulfillment_status` |
| `my-app/src/routes/test-treasury.tsx` | Full rewrite with 4 tabs, connect artist UI, wallet links |
| `my-app/src/components/concierto/ArtistRegistration.tsx` | Added Link Account feature (auth check, prospect linking) |

---

## Future Items (Noted, Not Urgent)

- **Platform View** — Dashboard for Buckets to observe platform distribution splits across all events
- **Fiat Hold Period** — 24–72 hour verification/clearance window before payouts are finalized
- **Platform Reserve User** — Create a real system user for double-entry accounting on platform credits
- **Add `'financial'` to `valid_event_category`** — DB migration to allow proper passport categorization
- **Profit Share Partners** — Table exists, endpoint supports it, but no test data yet
