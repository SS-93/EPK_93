# Session Summary: DNA System Integration Architecture

**Date:** February 3, 2026
**Session Focus:** DNA System Architecture Design & CALS Clarification
**Status:** Architecture Complete, Ready for Implementation

---

## 🎯 Session Accomplishments

### ✅ Major Deliverables Created

1. **`DNA_SYSTEM_INTEGRATION_ARCHITECTURE.md`** (Complete)
   - Full 4-domain data source mapping (A/T/G/C)
   - Implementation roadmap (7-8 weeks)
   - Integration patterns documented
   - Critical decisions identified
   - Event flow diagrams
   - Privacy approach defined

2. **Treasury Schema Documented**
   - Full schema review from migration scripts
   - Analytics views already exist (artist_revenue_summary, etc.)
   - Event flow patterns defined (Treasury → Passport → Coliseum)
   - G-Domain implementation plan ready (7-9 days)

3. **CALS System Clarified**
   - **MAJOR CORRECTION:** CALS = Cross-App Link Sync (NOT Community Activation & Loyalty)
   - Found existing types in `Desktop/93/my-app/src/types/cals.ts`
   - Confirmed CALS is separate from DNA domains
   - CALS = link-sharing attribution system, not behavioral mutations

---

## 📊 DNA System Status: Four Domains

### Current State

| Domain | Data Source | Status | Blocker |
|--------|-------------|--------|---------|
| **A-Domain** (Cultural) | MediaID Banks | Design Ready | Decision: Artist vs Listener MediaID |
| **T-Domain** (Behavioral) | Passport Logs | ✅ **OPERATIONAL** | None |
| **G-Domain** (Economic) | Treasury | Design Complete | None - Ready to implement |
| **C-Domain** (Spatial) | Vault Tour + MediaID | Design Ready | Need Vault schema review |

### T-Domain: ✅ Already Working
- Events: `player.track_played`, `player.track_paused`, `playlist.track_added`, etc.
- Processor generates T-Domain mutations
- Leaderboards operational
- Integration test passed (see MVP_QUICK_REFERENCE.md)

---

## 🗺️ Implementation Roadmap

### **Phase 1: G-Domain (Economic) - HIGH PRIORITY** ⚡
**Timeline:** 7-9 days
**Why First:** Aligns with Stripe production move, Treasury schema exists, clear ROI

**Tasks:**
1. Treasury → Passport event integration (Treasury writes economic events to passport_entries)
2. Extend Coliseum processor for G-Domain mutations
3. G-Domain leaderboards (coliseum_leaderboard_g_7d, g_30d, g_all_time)
4. Privacy-compliant display (normalized scores, not raw $)
5. Integration testing (treasury-integration-test.js)

**Blocker:** None

---

### **Phase 2: A-Domain (Cultural) - MEDIUM PRIORITY**
**Timeline:** 5-7 days (after decision)
**Why Second:** MediaID already exists, no external dependencies

**Blocker:** **DECISION NEEDED**

**Question:** How do we access MediaID data for cultural mutations?

**Options:**
- **A:** Artists create MediaID profiles (simple, self-reported)
- **B:** Aggregate from listener MediaID (audience-driven, privacy concerns)
- **C:** Hybrid - both artist + listener data **← Recommended**

**Once decided:**
1. Genre/interest alignment algorithms
2. A-Domain mutation logic
3. Cultural leaderboards
4. Privacy-compliant aggregation

---

### **Phase 3: C-Domain (Spatial) - MEDIUM PRIORITY**
**Timeline:** 5-7 days (after schema review)
**Why Third:** Requires Vault Tour Engine data

**Blocker:** Need Vault/Concierto schema review

**Questions:**
- Where is Vault data stored? (table names)
- How are artist performances tracked?
- Location format (lat/long, city codes, regions)?
- How do we link artists to Vaults?

**Once clarified:**
1. Location tracking implementation
2. Spatial mutation logic
3. Geographic leaderboards

---

### **Phase 4: T-Domain Enhancement - FUTURE**
**Timeline:** TBD
**Why Last:** T-Domain already functional for MVP

Potential enhancements:
- Social graph analysis
- Comment sentiment
- Engagement velocity
- Cross-platform tracking

---

## 🔑 Key Documents Created/Updated

### In `Buckets_SB/Documents/`:

1. **`DNA_SYSTEM_INTEGRATION_ARCHITECTURE.md`** (NEW - COMPREHENSIVE)
   - Complete architecture document
   - 4-domain data source mapping
   - Implementation plans
   - Decision frameworks
   - Event flow diagrams

2. **`MVP_QUICK_REFERENCE.md`** (Reviewed)
   - Coliseum MVP test protocol
   - Integration test passed ✅
   - Quick diagnostics commands
   - Next priorities documented

3. **`BUCKETS_MVP_TEST_PROTOCOL.md`** (Reviewed)
   - Detailed testing journey
   - Lessons learned
   - What made tests pass (90% = event queue management)

### In `Desktop/93/my-app/`:

4. **`src/types/cals.ts`** (Reviewed - Exists)
   - Complete CALS type definitions
   - Cross-App Link Sync system
   - NOT part of DNA T-Domain

5. **`tests/coliseum-integration-test.js`** (Reviewed - Working)
   - Successful integration test
   - Events → Mutations → Domain Strength → Leaderboards
   - Result: ✅ PASSED

6. **`documents/March_to_the_Finish.md`** (Reviewed)
   - 6-week V2 launch plan
   - CALS scoped but not yet implemented

---

## 💡 Critical Decisions Needed

### Decision 1: MediaID Access Pattern (Blocks A-Domain)
**Recommendation:** Option C (Hybrid)
- Artists define their own MediaID
- Also aggregate listener MediaID (with consent)
- Mutations factor both artist identity + audience affinity

---

### Decision 2: Vault Schema (Blocks C-Domain)
**Need to Review:**
- Vault table schema (venues, studios, spaces)
- Concierto events table (artist-venue linkage)
- Location data format
- Artist-Vault relationships

---

### Decision 3: Implementation Priority
**Current Recommendation:** G → A → C → T

**Rationale:**
- G-Domain ready now, aligns with Stripe production
- A-Domain next (after MediaID decision)
- C-Domain when Vault schema clarified
- T-Domain already working, enhancements can wait

**Alternative:** Could prioritize A-Domain if MediaID decision made quickly

---

## 📋 Treasury Schema (Documented)

### Key Tables:

1. **`ledger_entries`** - Core transaction ledger
   - user_id, type (credit/debit), amount_cents
   - event_source ('split', 'subscription', 'tip')
   - metadata (role, reason, split_percent, event_id)
   - wallet_id, passport_entry_id, verification_status

2. **`purchases`** - Purchase records
   - user_id, amount_cents, status
   - metadata (eventId, ticketTier, artistId)

3. **`subscriptions`** - Fan-to-artist subscriptions
   - fan_id, artist_id, tier_id
   - price_cents, billing_interval, status
   - stripe_subscription_id, locker_access_level

4. **`artist_subscription_tiers`** - Artist-defined tiers
   - artist_id, tier_name, price_min_cents
   - allow_custom_price, locker_access_level

5. **`platform_subscriptions`** - Artist-to-platform subscriptions
   - user_id, subscription_type, target_type
   - plan_name, price_cents, features, usage_limits

### Existing Analytics Views:
- `artist_revenue_summary` - Gross/net revenue per artist
- `artist_event_revenue` - Revenue per artist per event
- `artist_revenue_per_fan` - ARPU metric

---

## 🎯 G-Domain Implementation Plan (Ready to Start)

### Step-by-Step (7-9 days):

**Step 1:** Treasury → Passport Event Integration (1-2 days)
- Add Passport event logging to Treasury transaction handlers
- Event types: `treasury.subscription_payment`, `treasury.ticket_purchase`, `treasury.revenue_split_received`, `treasury.platform_subscription_payment`

**Step 2:** Extend Coliseum Processor (2-3 days)
- Update `generateMutations()` in `coliseum-processor/index.ts`
- Add G-Domain mutation logic (revenue magnitude, diversity, velocity)
- Implement `calculateGMagnitude()` helper

**Step 3:** Domain Strength Calculations (1 day)
- Extend `calculateDomainStrength()` for G-Domain
- Update aggregation logic

**Step 4:** G-Domain Leaderboards (1 day)
- Create views: `coliseum_leaderboard_g_7d`, `g_30d`, `g_all_time`
- Update refresh function

**Step 5:** Privacy-Compliant Display (1 day)
- Normalized scores (0-100 scale), not raw amounts
- Artist-only view for detailed revenue
- Public percentile rankings

**Step 6:** Integration Testing (1 day)
- Create `treasury-integration-test.js`
- Test: Purchase → Ledger → Passport → Mutation → Leaderboard
- Document results

---

## 🚨 CALS Clarification (IMPORTANT)

### What CALS Actually Is:

**CALS = Cross-App Link Sync** (NOT Community Activation & Loyalty)

**Purpose:**
- Privacy-first link-sharing attribution system
- Tracks Buckets link opens across external apps (iMessage, WhatsApp, Instagram)
- Auto-creates "shared threads" collecting links between users
- Revenue attribution for conversions
- NO message scraping - only tracks Buckets link opens

**Key Points:**
- CALS is **NOT part of DNA T-Domain behavioral mutations**
- CALS is a **separate system** for link attribution and revenue sharing
- Types already defined in `Desktop/93/my-app/src/types/cals.ts`
- Not yet implemented (no DB tables, no backend services)
- May feed analytics to Coliseum in future, but separate product layer

**CALS Components:**
- `cals_threads` - Conversation threads
- `cals_thread_items` - Links shared
- `cals_link_events` - Open tracking
- `cals_consent` - Privacy preferences
- `cals_shortlinks` - bkt.to/xyz mappings

**Integration Points:**
- Treasury: Attribution revenue
- Coliseum: Share funnel analytics
- MediaID: DNA-based share recommendations
- Locker: Brand drops in threads
- Concierto: Event links

---

## 📖 Reference: Event Flow Diagram

```
DATA SOURCES → PASSPORT → PROCESSOR → MUTATIONS → DOMAIN STRENGTH → LEADERBOARDS

A-Domain: MediaID Banks
          ↓
T-Domain: Passport Logs
          ↓
G-Domain: Treasury Ledger  →  passport_entries  →  coliseum-processor  →  coliseum_dna_mutations
          ↓                    (unified stream)      (batch every 5min)      (A/T/G/C mutations)
C-Domain: Vault Tour                                                                  ↓
          + MediaID                                                          coliseum_domain_strength
                                                                             (aggregated scores)
                                                                                      ↓
                                                                             Leaderboard Views
                                                                             (12 views: 4 domains × 3 time ranges)
```

---

## 🎯 Recommended Next Session Actions

### Priority 1: Start G-Domain Implementation
**If ready to code:**
1. Begin Treasury → Passport event integration
2. Target: Complete Step 1 in first session (1-2 days)
3. No blockers, clear path forward

### Priority 2: Make MediaID Decision
**If want to design A-Domain:**
1. Decide: Artist MediaID vs Listener aggregate vs Hybrid
2. Document decision rationale
3. Design genre/interest alignment algorithms
4. Plan A-Domain implementation

### Priority 3: Review Vault Schema
**If want to unlock C-Domain:**
1. Share Vault/Concierto table structures
2. Clarify location data format
3. Explain artist-venue relationships
4. Design spatial mutation logic

### Priority 4: CALS Implementation Plan
**If want to build CALS:**
1. Create CALS PRD based on spec provided
2. Database migration scripts
3. API endpoint specifications
4. MVP scope (4-6 weeks per spec)

---

## 📁 File Locations

### Backend (Buckets_SB):
- `/Users/pks.ml/Desktop/EPK-93/Buckets_SB/Documents/DNA_SYSTEM_INTEGRATION_ARCHITECTURE.md`
- `/Users/pks.ml/Desktop/EPK-93/Buckets_SB/Documents/MVP_QUICK_REFERENCE.md`
- `/Users/pks.ml/Desktop/EPK-93/Buckets_SB/Documents/BUCKETS_MVP_TEST_PROTOCOL.md`
- `/Users/pks.ml/Desktop/EPK-93/Buckets_SB/supabase/functions/coliseum-processor/index.ts`
- `/Users/pks.ml/Desktop/EPK-93/Buckets_SB/supabase/migrations/` (Treasury scripts)

### Frontend (Desktop/93/my-app):
- `/Users/pks.ml/Desktop/93/my-app/src/types/cals.ts`
- `/Users/pks.ml/Desktop/93/my-app/tests/coliseum-integration-test.js`
- `/Users/pks.ml/Desktop/93/my-app/documents/March_to_the_Finish.md`

---

## 🏆 Success Metrics

**When All Four Domains Operational:**
- ✅ T-Domain: Working now (Passport events)
- 🎯 G-Domain: 7-9 days to completion
- 🎯 A-Domain: 5-7 days (after MediaID decision)
- 🎯 C-Domain: 5-7 days (after Vault schema)

**Total Timeline:** ~3-4 weeks to full DNA system

**Result:**
- Holistic artist DNA scores (A/T/G/C + Total)
- 12 leaderboards (4 domains × 3 time ranges)
- Coliseum becomes authoritative artist analytics engine
- DNA powers recommendations, discovery, ecosystem insights
- Buckets differentiates from all other music platforms

---

## 💭 Philosophy

**"We are masters of pace"** - functionality over speed

- Each domain adds unique value
- Implement methodically, test thoroughly
- No rush, focus on quality
- Build for long-term ecosystem health

---

## 🚀 Next Session Quick Start

1. **Review this summary** (5 min)
2. **Choose priority:** G-Domain implementation, A-Domain design, C-Domain planning, or CALS PRD
3. **Make any pending decisions** (MediaID access, Vault schema review)
4. **Begin implementation or detailed planning**

**Ready to start G-Domain?** Say "start G-Domain implementation"
**Need to discuss strategy first?** Say "discuss priorities"
**Want CALS PRD?** Say "create CALS implementation plan"

---

**Session Date:** February 3, 2026
**Document Owner:** Engineering Team
**Status:** Architecture Complete ✅
**Next Milestone:** G-Domain Implementation (7-9 days)

---

**Philosophy:** Masters of pace. Functionality over speed. Build it right. 🎯
