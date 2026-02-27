# Buckets Research: Treasury Production & Badge System Focus

**Date:** February 15, 2026  
**Focus:** Treasury sandbox→production, Passport logging, ticketing, UI deployment, Badge auth system  
**Status:** Research Complete — Ready for Implementation

---

## 📋 Executive Summary

This document consolidates research across:
- **Backend:** `/Users/pks.ml/Desktop/EPK-93/Buckets_SB`
- **Frontend:** `/Users/pks.ml/Desktop/93/my-app`
- **Documents:** `Buckets_SB/Documents/` (DNA, MVP, Badge/Treasury plans)

**Today's focus:** Treasury production migration, Passport logging per user, actual ticketing, UI deployment, and badge-based auth system.

---

## 🏗️ Codebase Architecture

### Backend (Buckets_SB)
- **`server.js`** — Express server (~650 lines)
  - Stripe: checkout session, webhook, payment intent, portal
  - Passport: `/api/passport/log`, `/api/passport/stats`
  - Webhook handler: `handleCheckoutCompleted` → `fulfillTicket` → `applyRevenueSplits`
- **`supabase/functions/coliseum-processor/`** — Edge function for DNA mutations
- **`.env`** — Stripe test keys (`sk_test_...`, `whsec_...`)

### Frontend (Desktop/93/my-app)
- **`SmartRouteGuard`** — Uses `allowedRoles`, `profileState.selectedRole`
- **`useProfileRouting`** — Reads `profiles.role`, `media_ids.role`, `switchToRole` updates DB
- **`App.tsx`** — Routes with `allowedRoles={['fan','artist','brand','developer','admin']}`

### Current Auth Flow
- Single role per user in `profiles.role`
- Role switching: DB update → `profiles.role = targetRole`
- MediaID per role: `media_ids.user_uuid + role`
- SmartRouteGuard checks `allowedRoles.includes(profileState.selectedRole)`

---

## 💰 Treasury System: Current State

### What's Working

| Component | Status | Location |
|-----------|--------|----------|
| Stripe Checkout | ✅ | `server.js` L60–148 |
| Webhook (idempotency) | ✅ | `stripe_webhook_log` table |
| Purchase record | ✅ | `purchases` table |
| Ticket generation | ✅ | `fulfillTicket()` → `event_tickets` |
| Revenue splits | ✅ | `applyRevenueSplits()` → `ledger_entries` |
| Passport logging | ⚠️ Partial | `logPassportEvent()` uses `event_data`, `timestamp` |

### Passport Logging (Current)

**`logPassportEvent()` in server.js (L406–428):**
```javascript
await supabase.from('passport_entries').insert({
  user_id: userId,
  event_type: eventType,
  event_category: eventCategory,  // 'financial'
  event_data: payload,             // ⚠️ May be wrong column name
  timestamp: new Date().toISOString()
});
```

**Events currently logged:**
- `purchase.completed` (financial)
- `ticket.issued` (financial)
- `treasury.money_spent` (financial) — per artist for Coliseum
- `revenue.split_applied` (financial)
- `treasury.revenue_split_applied` (financial)

**Gap:** Coliseum processor expects `event_category: 'economic'` for G-domain but server uses `'financial'`. Also, `passport_entries` schema may use `metadata` not `event_data` — verify with API route at L318–332 which uses `metadata`.

### Gaps for Production

1. **Passport schema alignment:** Coliseum expects `metadata` for `amount_cents`, `artistId`, etc. Verify `passport_entries` columns.
2. **Event category:** Use `'economic'` for G-domain compatibility (DNA architecture doc).
3. **Ticket validation API:** Missing — BADGE_AUTH_TREASURY_PRODUCTION_PLAN specifies `/api/tickets/validate`.
4. **Stripe production keys:** Currently `.env` has `sk_test_...` — need `sk_live_...`, `whsec_...` for production webhook.
5. **Per-user Passport:** Events are logged with `user_id` — already per user. Ensure `entity_type` and `entity_id` set for artist attribution for G-domain.

---

## 🎫 Ticketing System

### Current Implementation

- **Ticket creation:** `fulfillTicket()` in server.js
- **Format:** `BKT-{YEAR}-{RANDOM}`, QR code data, validation secret
- **Tables:** `event_tickets` (user_id, event_id, purchase_id, ticket_code, qr_code_data, validation_secret, status, tier, perks)

### Missing (per BADGE_AUTH_TREASURY_PRODUCTION_PLAN)

- **`POST /api/tickets/validate`** — QR validation, redemption, double-scan prevention
- **Event date check** — Allow check-in 2 hours before event
- **Passport:** `concierto.ticket_redeemed` on redemption

---

## 🚀 Badge System Plan (Summary)

From `BADGE_AUTH_TREASURY_PRODUCTION_PLAN.md`:

### Current Issues
- Single role per user
- Role switching requires DB update
- Separate MediaID per role
- Onboarding friction per role

### Proposed Badge Architecture

1. **`user_badges`** table — multiple badges per user, `is_primary`, `verification_status`
2. **`profiles`** — `primary_badge`, `all_badges[]` instead of single `role`
3. **Default FAN badge** on signup
4. **Badge request flow** — artist badge requires admin approval
5. **`useBadges()`** hook — `activeBadge`, `switchBadge`, `setPrimaryBadge`
6. **SmartRouteGuard** — `requiredBadge` instead of `allowedRoles`
7. **BadgeSelector** — UI to switch badges without DB update

### Migration
- Phase 1: DB migration (roles → badges)
- Phase 2: Backend (badge API, approval)
- Phase 3: Frontend (useBadges, BadgeSelector, routes)
- Phase 4: Testing

**Timeline:** 7–11 days

---

## 📊 DNA System Context (from Session Docs)

- **T-Domain:** ✅ Operational (Passport → Coliseum)
- **G-Domain:** Ready — Treasury → Passport (`economic`) → Coliseum
- **A-Domain:** Blocked on MediaID decision
- **C-Domain:** Blocked on Vault schema

**Coliseum processor:** Uses `event_category: 'economic'` for G-domain. Check if `'financial'` is also handled.

---

## 🗂️ Implementation Checklist

### Treasury Production (Priority 1)

- [ ] **Passport schema:** Verify `passport_entries` columns (`metadata` vs `event_data`)
- [ ] **Event category:** Use `economic` for treasury events (Coliseum G-domain)
- [ ] **Entity attribution:** `entity_type: 'artist'`, `entity_id: artistId` for artist events
- [ ] **Stripe production:** Add `sk_live_...`, `pk_live_...`, production `whsec_...`
- [ ] **Webhook URL:** Configure `https://api.yourdomain.com/stripe/webhook`
- [ ] **Ticket validation:** Add `POST /api/tickets/validate` endpoint
- [ ] **Environment:** `.env.production` for backend and frontend

### Badge System (Priority 2)

- [ ] Create `user_badges` table migration
- [ ] Migrate `profiles.role` → badges
- [ ] Add `primary_badge`, `all_badges` to profiles
- [ ] Build `useBadges()` hook
- [ ] Update SmartRouteGuard to `requiredBadge`
- [ ] Build BadgeSelector component
- [ ] Badge request/approval API

### UI Deployment

- [ ] Build: `npm run build` (frontend)
- [ ] Deploy server.js (Railway, Heroku, AWS)
- [ ] DNS: app.yourdomain.com, api.yourdomain.com
- [ ] SSL, CORS, env vars

---

## 📁 Key File References

| Purpose | Path |
|---------|------|
| Backend server | `Buckets_SB/server.js` |
| Coliseum processor | `Buckets_SB/supabase/functions/coliseum-processor/index.ts` |
| SmartRouteGuard | `my-app/src/components/SmartRouteGuard.tsx` |
| useProfileRouting | `my-app/src/components/useProfileRouting.ts` |
| Badge/Treasury plan | `Buckets_SB/Documents/BADGE_AUTH_TREASURY_PRODUCTION_PLAN.md` |
| DNA architecture | `Buckets_SB/Documents/DNA_SYSTEM_INTEGRATION_ARCHITECTURE.md` |
| Quick start | `Buckets_SB/Documents/QUICK_START_NEXT_SESSION.md` |

---

## 🔑 Recommended Order

1. **Treasury production first** (revenue-critical)
   - Fix Passport schema/event_category
   - Add ticket validation API
   - Switch to production Stripe keys
   - Deploy backend + UI

2. **Badge system second** (UX improvement)
   - Can run in parallel with production
   - 7–11 days per plan

---

**Document Status:** ✅ Research Complete  
**Next:** Begin implementation per BADGE_AUTH_TREASURY_PRODUCTION_PLAN.md
