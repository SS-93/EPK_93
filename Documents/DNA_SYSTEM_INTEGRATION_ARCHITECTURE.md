# DNA System Integration Architecture

**Date:** February 3, 2026
**Status:** Design Phase
**Philosophy:** "We are masters of pace" - functionality over speed

---

## 🧬 Overview

The Coliseum DNA system tracks artist evolution across four domains (A/T/G/C), each powered by distinct data sources within the Buckets ecosystem.

**Current State:** T-Domain operational with Passport events
**Goal:** Full DNA system with all four domains integrated

---

## 📊 Domain Data Source Mapping

### A-Domain: Cultural Mutations
**Data Sources:** MediaID Banks

**What MediaID Provides:**
- `interests`: Array of 13 interest categories (Music, Art, Technology, Fashion, Food, Travel, Sports, Gaming, Movies, Books, Photography, Fitness, Nature)
- `genre_preferences`: Array of 13 music genres (Hip Hop, R&B, Pop, Rock, Electronic, Jazz, Classical, Country, Reggae, Latin, Alternative, Indie, Folk)
- `location_code`: Optional city/region string

**Integration Questions:**
1. **Trigger Point:** When should we generate A-Domain mutations?
   - On MediaID profile creation/update?
   - When user with MediaID interacts with artist?
   - During batch processing (similar to Passport events)?

2. **Mutation Logic:** How do we convert MediaID data to cultural mutations?
   - Genre alignment: Calculate overlap between artist genres and user genre_preferences?
   - Interest matching: Score artist content against user interests?
   - Location affinity: Bonus for artist-user location matches?

3. **Data Access:** Where does artist MediaID data live?
   - Do artists have MediaID profiles?
   - Or do we aggregate from their listeners' MediaID data?
   - Privacy: How do we anonymize user MediaID data in artist analytics?

4. **Mutation Strength:** What determines A-Domain mutation magnitude?
   - Number of matching genres/interests?
   - Weighted by popularity of those preferences?
   - Time-decay for stale MediaID data?

---

### T-Domain: Behavioral Mutations
**Data Sources:** Passport Logs Only (for now)

**What's Working Today:**
- Passport events captured: `player.track_played`, `player.track_paused`, `playlist.track_added`, etc.
- Processor generates T-Domain mutations from engagement events
- Domain strength calculated from mutation accumulation

**Behavioral Signals (Current):**
- **Digital Engagement:**
  - Track plays (duration, completion %)
  - Track skips
  - Playlist adds
  - Likes/favorites
  - Shares (via native share sheet)
  - Artist follows
  - Profile views
  - Comment submissions

- **Platform Interactions:**
  - Event RSVPs (via Concierto)
  - Ticket purchases (logged to Passport)
  - Content uploads (artist activity)
  - Voting participation (tournament rounds)

**T-Domain Mutation Logic:**

The Coliseum processor generates T-Domain mutations from engagement events:

```javascript
// T-Domain: Behavioral signals (engagement depth)
if (event.event_category === 'interaction') {
  const tMagnitude = calculateTMagnitude({
    event_type: event.event_type,
    completion_pct: event.metadata?.completion_pct || 0,
    duration_seconds: event.metadata?.duration_seconds || 0,
    engagement_depth: event.metadata?.engagement_depth || 'medium',
    source: event.metadata?.source
  });

  if (tMagnitude > 0) {
    mutations.push({
      artist_id: artistId,
      domain: 'T',
      magnitude: tMagnitude,
      base_value: engagement_score,
      metadata: {
        event_type: event.event_type,
        engagement_depth: event.metadata?.engagement_depth
      }
    });
  }
}
```

**Mutation Factors:**
- **Play completion:** Full plays > partial plays > skips
- **Repeat plays:** Returning listeners = strong engagement
- **Active interactions:** Likes/shares > passive listening
- **Consistency:** Regular engagement > one-time spikes
- **Session depth:** Long sessions = higher engagement quality

**Future Enhancements:**
- Social graph analysis (follower network quality)
- Comment sentiment analysis
- Engagement velocity (growth rate)
- Cross-platform tracking (if available)

**Note on CALS:**
CALS (Cross-App Link Sync) is a separate system for link-sharing attribution across external apps (iMessage, WhatsApp, etc.). While CALS may eventually feed engagement signals to Coliseum, it is NOT currently part of T-Domain behavioral mutations. CALS focuses on:
- Link share tracking
- Attribution revenue
- Thread-based conversations
- Referral analytics

See `src/types/cals.ts` for CALS implementation details.

---

### G-Domain: Economic Mutations
**Data Sources:** Treasury System

**Treasury Overview:**
- Payments, settlements, splits, artist earnings
- Vault Tour Engine integration: Ticket sales, venue splits, merch
- Subscription system: Artist-to-fan and artist-to-platform subscriptions

**Treasury Schema (Existing Tables):**

1. **`ledger_entries`** - Core transaction ledger
   - `id` (UUID)
   - `user_id` (UUID) - Artist or fan receiving/sending funds
   - `type` (TEXT) - 'credit' or 'debit'
   - `amount_cents` (INTEGER) - Transaction amount in cents
   - `event_source` (TEXT) - 'split', 'subscription', 'tip', 'purchase'
   - `reference_id` (TEXT) - Links to purchases, subscriptions, etc.
   - `metadata` (JSONB) - Contains:
     - `role` ('artist', 'venue', 'platform', 'fan')
     - `reason` ('ticket', 'tip', 'subscription', 'purchase')
     - `split_percent` (NUMERIC) - Revenue split percentage
     - `event_id` (UUID) - Concierto event reference
     - `purchase_id` (UUID) - Purchase reference
   - `wallet_id` (TEXT) - HMAC-SHA256 hash for privacy
   - `passport_entry_id` (UUID) - Reference to Passport entry
   - `verification_status` (TEXT) - 'pending', 'verified', 'failed', 'flagged'
   - `created_at` (TIMESTAMPTZ)

2. **`purchases`** - Purchase records
   - `id` (UUID)
   - `user_id` (UUID) - Fan making purchase
   - `amount_cents` (INTEGER) - Total purchase amount
   - `status` (TEXT) - 'pending', 'completed', 'refunded'
   - `metadata` (JSONB) - Contains:
     - `eventId` (UUID) - Concierto event
     - `ticketTier` (TEXT) - Ticket type
     - `artistId` (UUID) - Artist receiving payment

3. **`subscriptions`** - Fan-to-artist subscriptions
   - `id` (UUID)
   - `fan_id` (UUID) - Subscribing user
   - `artist_id` (UUID) - Artist being subscribed to
   - `tier_id` (UUID) - References artist_subscription_tiers
   - `price_cents` (INTEGER) - Monthly/annual price
   - `custom_price_cents` (INTEGER) - Custom price if fan paid more
   - `billing_interval` (TEXT) - 'monthly', 'annual'
   - `status` (TEXT) - 'active', 'canceled', 'paused', 'expired'
   - `stripe_subscription_id` (TEXT)
   - `current_period_start` (TIMESTAMPTZ)
   - `current_period_end` (TIMESTAMPTZ)
   - `locker_access_level` (TEXT) - 'free', 'basic', 'premium', 'vip', 'all'

4. **`artist_subscription_tiers`** - Artist-defined subscription tiers
   - `id` (UUID)
   - `artist_id` (UUID)
   - `tier_name` (TEXT) - 'Basic', 'Premium', 'VIP'
   - `price_min_cents` (INTEGER) - Minimum $1.00 (100 cents)
   - `allow_custom_price` (BOOLEAN) - Allow fans to pay more
   - `locker_access_level` (TEXT) - Content access level
   - `subscriber_count` (INTEGER)

5. **`platform_subscriptions`** - Artist-to-platform subscriptions
   - `id` (UUID)
   - `user_id` (UUID) - Artist subscribing
   - `subscription_type` (TEXT) - 'artist_platform', 'brand_platform'
   - `target_type` (TEXT) - 'coliseum', 'concierto_pro', 'companon_pro'
   - `plan_name` (TEXT) - 'free', 'starter', 'basic', 'pro', 'enterprise'
   - `price_cents` (INTEGER)
   - `features` (JSONB) - Feature flags
   - `usage_limits` (JSONB) - API calls, events, campaigns limits
   - `usage_current` (JSONB) - Current usage tracking

**Treasury Analytics Views (Already Exist):**
- `artist_revenue_summary` - Gross/net revenue per artist
- `artist_event_revenue` - Revenue breakdown per artist per event
- `artist_revenue_per_fan` - Revenue Per Fan metric (SUM(amount) / COUNT(DISTINCT fans))

**G-Domain Event Flow:**

Treasury writes to `passport_entries` after successful transactions:

```javascript
// Example 1: Subscription payment processed
await supabase.from('passport_entries').insert({
  user_id: fan_id,
  event_type: 'treasury.subscription_payment',
  event_category: 'economic',
  entity_type: 'artist',
  entity_id: artist_id,
  metadata: {
    amount_cents: 2900,  // $29.00
    currency: 'USD',
    transaction_type: 'subscription',
    subscription_id: subscription_id,
    tier: 'premium',
    billing_interval: 'monthly',
    ledger_entry_id: ledger_entry_id,
    reference_id: reference_id,
    source: 'treasury'
  }
});

// Example 2: Ticket purchase (with splits)
await supabase.from('passport_entries').insert({
  user_id: fan_id,
  event_type: 'treasury.ticket_purchase',
  event_category: 'economic',
  entity_type: 'artist',
  entity_id: artist_id,
  metadata: {
    amount_cents: 5000,  // $50.00
    artist_split_cents: 3500,  // $35.00 (70%)
    venue_split_cents: 1000,   // $10.00 (20%)
    platform_split_cents: 500,  // $5.00 (10%)
    transaction_type: 'ticket',
    event_id: concierto_event_id,
    purchase_id: purchase_id,
    ledger_entry_id: ledger_entry_id,
    source: 'treasury'
  }
});

// Example 3: Artist receives split payout
// (This goes to artist's ledger as 'credit')
await supabase.from('passport_entries').insert({
  user_id: artist_id,
  event_type: 'treasury.revenue_split_received',
  event_category: 'economic',
  entity_type: 'artist',
  entity_id: artist_id,
  metadata: {
    amount_cents: 3500,  // Artist's share
    split_percent: 70.0,
    transaction_type: 'split',
    reason: 'ticket',
    event_id: concierto_event_id,
    ledger_entry_id: ledger_entry_id,
    source: 'treasury'
  }
});

// Example 4: Platform subscription (artist-to-platform)
await supabase.from('passport_entries').insert({
  user_id: artist_id,
  event_type: 'treasury.platform_subscription_payment',
  event_category: 'economic',
  entity_type: 'platform',
  entity_id: null,
  metadata: {
    amount_cents: 9900,  // $99.00/month Pro plan
    plan_name: 'pro',
    target_type: 'coliseum',
    billing_interval: 'monthly',
    features: ['advanced_analytics', 'api_access', 'realtime_updates'],
    source: 'treasury'
  }
});
```

**G-Domain Mutation Logic:**

Coliseum processor generates G-Domain mutations from economic events:

**Mutation Strength Calculation:**
- **Revenue magnitude:** Higher amounts = stronger mutations
- **Transaction frequency:** Consistent revenue > one-time spikes
- **Revenue diversity:** Multiple streams (tickets + subscriptions + tips) boost strength
- **Split fairness:** Artists with fair venue splits score higher
- **Subscription count:** More subscribers = sustained economic momentum
- **Revenue per fan:** Higher ARPU = better monetization

**Mutation Factors:**
```javascript
// G-Domain mutation magnitude calculation
const magnitude = calculateGMagnitude({
  amount_cents: event.metadata.amount_cents,
  transaction_type: event.metadata.transaction_type,
  revenue_velocity: getRevenueVelocity(artist_id, '7d'),  // $ per week
  transaction_frequency: getTransactionCount(artist_id, '30d'),
  revenue_diversity: getRevenueStreams(artist_id),  // count of unique types
  subscription_count: getSubscriberCount(artist_id),
  revenue_per_fan: getRevenuePerFan(artist_id)
});

// Generate mutation
const mutation = {
  artist_id: artist_id,
  domain: 'G',
  magnitude: magnitude,
  base_value: event.metadata.amount_cents / 100,  // Convert to dollars
  metadata: {
    transaction_type: event.metadata.transaction_type,
    amount_cents: event.metadata.amount_cents,
    revenue_velocity: revenue_velocity,
    transaction_frequency: transaction_frequency,
    revenue_diversity: revenue_diversity
  }
};
```

**Privacy & Leaderboard Display:**
- **Leaderboards:** Show normalized G-Domain strength scores (0-100 scale), NOT raw dollar amounts
- **Artist Dashboard:** Show actual revenue privately (only visible to artist)
- **Public View:** "High economic momentum" vs "$50,000 earned"
- **Percentile Ranking:** "Top 10% of earners" vs raw amounts

**Integration Priority:** HIGH - Phase 1 (aligns with Stripe production move)

---

### C-Domain: Spatial Mutations
**Data Sources:** MediaID Location + Vault Tour Engine

**Vault Tour Engine Components:**
1. **Vault (Places):**
   - Studios, venues, creative spaces
   - Each Vault has location, capacity, amenities
   - Artists can claim/verify Vaults they've performed at

2. **Concierto (Events):**
   - Live shows, studio sessions, collaborations
   - Event has Vault (location), date/time, participants, tickets

3. **Treasury Connection:**
   - Ticket sales flow through Treasury
   - Venue splits, artist payouts tracked

**Integration Questions:**
1. **What Triggers C-Domain Mutations?**
   - Artist performs at new Vault location?
   - Artist tours across multiple cities?
   - Fans travel to see artist (distance metrics)?
   - Artist-fan location alignment from MediaID?

2. **Spatial Metrics:**
   - Geographic reach: Number of unique cities/countries?
   - Local strength: Concentration of fans in home region?
   - Tour momentum: Frequency of performances across locations?
   - Digital vs physical: Streaming locations vs show locations?

3. **Data Access:**
   - Vault schema: What tables store Vault/Concierto data?
   - Location format: lat/long? city names? region codes?
   - Event participation: How do we know which artists performed at which Vaults?

4. **MediaID + Vault Synthesis:**
   - MediaID provides user location_code (optional, privacy-controlled)
   - Vault provides artist performance locations
   - Mutation logic: Artist playing in user's home city? Artist expanding to new regions where fans are?

---

## 💬 CALS (Cross-App Link Sync) - Separate System

**IMPORTANT:** CALS is NOT part of DNA Domain mutations. It's a separate link-sharing and attribution system.

### What is CALS?

**CALS = Cross-App Link Sync**

A privacy-first, attribution-powered link-sharing system that connects users across external messaging apps (iMessage, WhatsApp, Instagram, etc.) without reading their private messages.

### How CALS Works:

1. **User shares Buckets link** (track, event, artist) via ANY external app
2. **Recipient opens link** → deep link fires → Buckets app opens
3. **CALS tracks the open event** (sender_id, receiver_id, link_id, source_app)
4. **Auto-creates a "shared thread"** collecting all Buckets links between these users
5. **Revenue attribution** → conversions from link opens credited to sharer
6. **No message scraping** → only tracks when Buckets links are opened

### Key Components:

**Tables:**
- `cals_threads` - Conversation threads
- `cals_thread_items` - Links shared in threads
- `cals_link_events` - Link open tracking
- `cals_consent` - User privacy preferences
- `cals_shortlinks` - bkt.to/xyz shortlink mapping

**Features:**
- Rich link previews (track, event, artist cards)
- Attribution revenue tracking
- DNA-based share recommendations
- Brand drops in threads (opt-in via Locker)
- Analytics via Coliseum

**Privacy:**
- All features opt-in via MediaID consent scopes
- No external message content read
- Only Buckets link opens tracked
- User can delete threads/data anytime

### Integration Points with Buckets Ecosystem:

1. **Treasury:** Attribution revenue from link conversions
2. **Coliseum:** Share funnel analytics (share → open → conversion)
3. **MediaID:** DNA-based share recommendations
4. **Locker:** Brand drops attached to threads (opt-in)
5. **Concierto:** Event links in threads
6. **Sync Library:** Sync brief links shareable

### CALS Implementation Status:

- **Types defined:** ✅ (`src/types/cals.ts`)
- **Database schema:** ❌ Not created yet
- **Backend services:** ❌ Not implemented
- **Frontend components:** ❌ Not built
- **Deep linking:** ❌ Not configured
- **Attribution logic:** ❌ Not implemented

### Future: CALS → Coliseum Analytics

CALS may eventually feed data to Coliseum for analytics:
- Share velocity (links shared per artist)
- Viral coefficient (how many opens per share)
- Conversion funnels (share → open → action)
- Network effects (multi-hop sharing)

**But CALS is NOT part of DNA T-Domain behavioral mutations.**

---

## 🏗️ Implementation Priorities

### Phase 1: G-Domain (Economic) - HIGH PRIORITY ⚡
**Why First:**
- Stripe moving to production (immediate need)
- Treasury schema already exists and is well-documented
- Clear mutation triggers (transactions already tracked in ledger_entries)
- High user value (artists see earnings impact on DNA)
- Analytics views already built (artist_revenue_summary, artist_event_revenue)

**Implementation Plan:**

**Step 1.1: Treasury → Passport Event Integration (1-2 days)**
- Add Passport event logging to Treasury transaction handlers
- Event types to implement:
  - `treasury.subscription_payment` (fan-to-artist)
  - `treasury.ticket_purchase` (Concierto events)
  - `treasury.revenue_split_received` (artist payouts)
  - `treasury.platform_subscription_payment` (artist-to-platform)
  - `treasury.tip_received` (fan tips)
- Location: Treasury payment processing logic (wherever ledger_entries are created)
- Test: Verify events flow to passport_entries after transactions

**Step 1.2: Extend Coliseum Processor for G-Domain (2-3 days)**
- Update `generateMutations()` function in `coliseum-processor/index.ts`
- Add G-Domain mutation logic:
  ```typescript
  // G-Domain: Economic signals
  if (event.event_category === 'economic') {
    const gMagnitude = calculateGMagnitude({
      amount_cents: event.metadata?.amount_cents || 0,
      transaction_type: event.metadata?.transaction_type,
      // Query revenue velocity, diversity, etc. from Treasury views
    });

    if (gMagnitude > 0) {
      mutations.push({
        artist_id: artistId,
        domain: 'G',
        magnitude: gMagnitude,
        base_value: (event.metadata?.amount_cents || 0) / 100,
        metadata: {
          transaction_type: event.metadata?.transaction_type,
          amount_cents: event.metadata?.amount_cents,
          event_id: event.metadata?.event_id
        }
      });
    }
  }
  ```
- Implement `calculateGMagnitude()` helper function
- Test: Process Treasury events, verify G-Domain mutations created

**Step 1.3: Update Domain Strength Calculations (1 day)**
- Extend `calculateDomainStrength()` to include G-Domain
- Add G-Domain column to `coliseum_domain_strength` table (if not exists)
- Update aggregation logic to sum G-Domain mutations
- Test: Verify G-Domain strength calculated correctly

**Step 1.4: Add G-Domain to Leaderboards (1 day)**
- Create view: `coliseum_leaderboard_g_7d` (G-Domain leaderboard)
- Create view: `coliseum_leaderboard_g_30d`
- Create view: `coliseum_leaderboard_g_all_time`
- Update `refresh_all_coliseum_leaderboards()` function to include G-Domain
- Test: Verify G-Domain leaderboards populate

**Step 1.5: Privacy-Compliant Display (1 day)**
- Ensure leaderboards show normalized scores, not raw amounts
- Add artist-only view for detailed revenue breakdown
- Update frontend to display G-Domain strength
- Test: Verify no raw financial data exposed in public views

**Step 1.6: Integration Testing (1 day)**
- Create `treasury-integration-test.js` similar to `coliseum-integration-test.js`
- Test flow: Purchase → Ledger Entry → Passport Event → Mutation → Domain Strength → Leaderboard
- Verify all transaction types (subscriptions, tickets, tips, splits)
- Document results in `TREASURY_MVP_TEST_PROTOCOL.md`

**Total Estimated Effort:** 7-9 days

**Success Criteria:**
- [ ] Treasury transactions generate Passport events
- [ ] G-Domain mutations created from economic events
- [ ] Domain strength includes G-Domain calculations
- [ ] G-Domain leaderboards operational
- [ ] Privacy: Raw amounts hidden, scores normalized
- [ ] Integration test passes end-to-end

---

### Phase 2: A-Domain (Cultural) - MEDIUM PRIORITY
**Why Second:**
- MediaID already implemented in frontend
- Rich data source (interests, genres, location)
- Enhances artist-fan matching
- No external system dependencies

**Tasks:**
1. Clarify MediaID access patterns (artist vs listener data)
2. Design genre/interest alignment algorithms
3. Create batch processor or real-time mutation triggers
4. Privacy: Anonymize aggregated MediaID data
5. Update leaderboards for A-Domain

---

### Phase 3: C-Domain (Spatial) - MEDIUM PRIORITY
**Why Third:**
- Vault Tour Engine in active development
- Requires MediaID + Vault data synthesis
- Powerful differentiation (location-based rankings)
- Depends on Phase 2 (MediaID access patterns)

**Tasks:**
1. Define Vault/Concierto schema
2. Track artist performance locations
3. Aggregate fan locations from MediaID
4. Design spatial mutation algorithms
5. Consider privacy for location data

---

### Phase 4: T-Domain Enhancement - FUTURE
**Why Last:**
- T-Domain already working with Passport (digital engagement)
- Additional behavioral signals can be added incrementally
- No blockers for MVP launch

**Potential Enhancements:**
- Social graph analysis (network quality, influencer detection)
- Comment sentiment analysis
- Engagement velocity tracking
- Cross-platform engagement (if available)
- Video view completion tracking
- Session quality scoring

**No immediate implementation plan** - T-Domain is functional for MVP

---

## 🔑 Critical Design Questions

### 1. Data Flow Pattern
**Question:** Should all domains flow through passport_entries, or separate processors?

**Option A: Unified Passport (Recommended)**
- All events → passport_entries table
- Single processor handles all domains
- Consistent FIFO queue, batch processing
- New column: `domain_hint` ('A', 'T', 'G', 'C') to route mutation logic

**Option B: Domain-Specific Tables**
- treasury_events, mediaid_events, vault_events, passport_entries
- Separate processors for each domain
- More complex, harder to coordinate, but more modular

**Recommendation:** Option A. Keep it simple, leverage existing Passport infrastructure.

---

### 2. Privacy & Consent
**Question:** How do we handle sensitive data (financials, location, personal interests)?

**Considerations:**
- G-Domain: Artist earnings are sensitive. Leaderboard shows scores, not raw $?
- C-Domain: User location from MediaID is privacy-controlled. Aggregate only?
- A-Domain: User interests/genres aggregated, never expose individual MediaID data?

**Recommendation:**
- Leaderboards show normalized domain_strength scores (0-100 scale?)
- Raw financial/location data never exposed in public views
- Artist dashboard shows their own raw data privately
- Require user consent flags from MediaID privacy_settings before using data

---

### 3. Real-Time vs Batch Processing
**Question:** Do mutations generate instantly or during scheduled batch runs?

**Current:** T-Domain uses batch processing (CRON every 5 min, or manual trigger)

**Options:**
- Real-time: Event arrives → immediate mutation generation → instant leaderboard update (complex, expensive)
- Batch: Events queue up → processor runs periodically → bulk mutations (current, scalable)
- Hybrid: High-value events (G-Domain transactions) real-time, others batched?

**Recommendation:** Keep batch processing for all domains. 5-minute delay is acceptable for MVP.

---

### 4. Treasury Integration Approach
**Question:** How does Treasury communicate transactions to DNA system?

**Option A: Treasury writes to passport_entries**
```javascript
// In Treasury system after payment
await supabase.from('passport_entries').insert({
  user_id: fan_id,
  event_type: 'treasury.payment_received',
  event_category: 'economic',
  entity_type: 'artist',
  entity_id: artist_id,
  metadata: {
    amount: 10.00,
    currency: 'USD',
    transaction_type: 'streaming_royalty',
    transaction_id: 'txn_xyz123'
  }
});
```

**Option B: Processor pulls from Treasury tables**
```javascript
// In coliseum-processor
const { data: transactions } = await supabase
  .from('treasury_transactions')
  .select('*')
  .is('coliseum_processed_at', null)
  .order('created_at', { ascending: true });
```

**Recommendation:** Option A. Unified event stream. Treasury is source of truth, Passport is event log.

---

## 📋 Immediate Next Steps

### ✅ Completed Understanding:
1. ✅ **CALS Defined:** Community Activation & Loyalty System - participation protocol for live engagement
2. ✅ **Treasury Schema Reviewed:** Full schema documented (ledger_entries, purchases, subscriptions, etc.)
3. ✅ **Event Flows Designed:** Treasury → Passport and CALS → Passport integration patterns defined

### 🎯 Ready to Implement:
1. **Start G-Domain Implementation (Phase 1)**
   - Begin with Treasury → Passport event integration
   - Extend processor for G-Domain mutations
   - Target: 7-9 days to completion
   - **Blocker:** None. Treasury schema exists, integration pattern clear.

2. **Plan A-Domain Integration (Phase 2)**
   - Clarify MediaID access patterns (decision needed):
     - Do artists have MediaID profiles?
     - Or aggregate from listener MediaID data?
   - Design genre/interest alignment algorithms
   - Target: 5-7 days after decision

3. **Define C-Domain Schema (Phase 3)**
   - **Blocker:** Need Vault/Concierto schema review
   - Questions:
     - Where is Vault data stored (table names)?
     - How are artist performances tracked?
     - Location format (lat/long, city codes, regions)?
   - Target: Can start planning once schema reviewed

4. **Privacy Policy Documentation**
   - Document data usage across all domains
   - Define consent requirements (especially MediaID)
   - Anonymization approach for financial/location data
   - Leaderboard display rules (normalized scores, no raw $)

---

## 🎯 Success Criteria

**G-Domain (Economic):**
- [ ] Stripe production payments generate G-Domain mutations
- [ ] Leaderboard shows economic domain strength
- [ ] Artist dashboard shows revenue impact on DNA

**A-Domain (Cultural):**
- [ ] MediaID data feeds cultural mutations
- [ ] Genre/interest alignment calculated
- [ ] Privacy-compliant aggregation

**C-Domain (Spatial):**
- [ ] Vault performance locations tracked
- [ ] Fan location aggregated from MediaID
- [ ] Spatial mutations reflect geographic reach

**T-Domain (CALS):**
- [ ] CALS system defined and scoped
- [ ] New behavioral signals integrated
- [ ] Enhanced engagement tracking

---

## 🗺️ Implementation Roadmap

```
NOW (Weeks 1-2): G-Domain Implementation
├─ Treasury → Passport event integration
├─ Extend processor for economic mutations
├─ G-Domain leaderboards
└─ Integration testing

NEXT (Weeks 3-4): A-Domain Implementation
├─ Clarify MediaID access pattern (DECISION NEEDED)
├─ Genre/interest alignment algorithms
├─ A-Domain mutation logic
└─ Cultural leaderboards

THEN (Weeks 5-6): C-Domain Implementation
├─ Vault schema review (BLOCKER)
├─ Location tracking implementation
├─ Spatial mutation logic
└─ Geographic leaderboards

LATER (Weeks 7-8): T-Domain Enhancement (CALS)
├─ CALS event integration
├─ Physical engagement signals
├─ Enhanced T-Domain mutations
└─ Live activation tracking

ONGOING: Privacy & Analytics
├─ Privacy policy documentation
├─ Consent management
├─ Leaderboard normalization
└─ Artist dashboard enhancements
```

---

## 🔑 Key Decisions Needed

### Decision 1: MediaID Access Pattern (Blocks A-Domain)
**Question:** How do we access MediaID data for A-Domain mutations?

**Option A: Artist MediaID Profiles**
- Artists create their own MediaID (genres, interests, location)
- Mutations based on artist's self-defined cultural DNA
- Pros: Simple, direct, artist-controlled
- Cons: Self-reported data, no audience signal

**Option B: Aggregate Listener MediaID**
- Mutations based on aggregated listener MediaID data
- "This artist attracts fans who like X, Y, Z"
- Pros: Audience-driven, authentic signal, dynamic
- Cons: Privacy concerns, requires consent, complex aggregation

**Option C: Hybrid (Recommended)**
- Artists have MediaID profiles
- Also aggregate listener MediaID (with consent)
- Mutations factor both artist identity + audience affinity
- Pros: Best of both worlds, rich data
- Cons: More complex implementation

**Recommendation:** Start with Option C. Artists define their MediaID, we enhance with listener data where consent given.

---

### Decision 2: Vault Schema & Location Tracking (Blocks C-Domain)
**Question:** Where is Vault/Concierto data stored? How do we track locations?

**Need to Review:**
- Vault table schema (venues, studios, creative spaces)
- Concierto events table (links artists to Vaults)
- Location data format (lat/long, city codes, regions)
- Artist-Vault relationships (performances, residencies)

**Once Clarified:**
- Design C-Domain mutation logic
- Implement spatial tracking
- Create geographic leaderboards

---

### Decision 3: Privacy & Leaderboard Display
**Question:** How do we display sensitive data (money, location) in leaderboards?

**Approach (Recommended):**
- **Leaderboards:** Show normalized domain_strength scores (0-100 scale)
  - Example: "G-Domain: 87.5" instead of "$45,230 earned"
- **Artist Dashboard:** Show actual data privately
  - Example: "Total Revenue: $45,230 | G-Domain Score: 87.5"
- **Percentile Rankings:** Show relative position
  - Example: "Top 5% in G-Domain (Economic)" instead of raw amounts
- **Consent-Based:** Only include data where user consent given
  - MediaID location: Only aggregate if `privacy_settings.location_access = true`
  - Financial data: Artist can opt out of public G-Domain leaderboards

**Implementation:**
- Build anonymization into query/view layer
- Store raw data in mutations, transform for display
- Add opt-in/opt-out flags to artist profiles

---

## 📊 DNA System Data Flow (Complete)

```
┌─────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  A-DOMAIN (Cultural)      │  MediaID Banks                      │
│  ├─ Artist MediaID        │  ├─ Interests                       │
│  └─ Listener MediaID      │  ├─ Genre preferences               │
│                           │  └─ Location code                   │
│                                                                 │
│  T-DOMAIN (Behavioral)    │  Passport + CALS                    │
│  ├─ Digital engagement    │  ├─ Track plays, skips, adds        │
│  └─ Physical engagement   │  ├─ Event attendance                │
│                           │  ├─ Dwell time, interactions        │
│                           │  └─ Feedback, ratings               │
│                                                                 │
│  G-DOMAIN (Economic)      │  Treasury                           │
│  ├─ Subscriptions         │  ├─ Ledger entries                  │
│  ├─ Ticket sales          │  ├─ Revenue splits                  │
│  ├─ Tips & purchases      │  ├─ Purchase records                │
│  └─ Platform fees         │  └─ Subscription data               │
│                                                                 │
│  C-DOMAIN (Spatial)       │  Vault Tour + MediaID               │
│  ├─ Performance locations │  ├─ Vault venues                    │
│  ├─ Fan locations         │  ├─ Concierto events                │
│  └─ Geographic reach      │  └─ Location aggregates             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                       PASSPORT ENTRIES                          │
│  (Unified Event Stream - All domains flow here)                 │
│                                                                 │
│  event_category: 'interaction' | 'economic' | 'cultural' etc.   │
│  metadata: Domain-specific data                                 │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                   COLISEUM PROCESSOR                            │
│  (Edge Function - Batch Processing Every 5 Min)                 │
│                                                                 │
│  1. Fetch unprocessed events (FIFO, batch size 100)             │
│  2. Generate mutations per domain:                              │
│     ├─ A-Domain: Genre/interest alignment                       │
│     ├─ T-Domain: Engagement depth + physical presence           │
│     ├─ G-Domain: Revenue magnitude + diversity                  │
│     └─ C-Domain: Geographic reach + location affinity           │
│  3. Calculate domain_strength per artist                        │
│  4. Update leaderboards                                         │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                   COLISEUM_DNA_MUTATIONS                        │
│  (Individual mutation records per artist per domain)            │
│                                                                 │
│  artist_id, domain, magnitude, base_value, metadata             │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                COLISEUM_DOMAIN_STRENGTH                         │
│  (Aggregated strength scores per artist per domain)             │
│                                                                 │
│  entity_id, entity_type, time_range,                            │
│  a_strength, t_strength, g_strength, c_strength, total_strength │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                     LEADERBOARDS                                │
│  (Materialized Views - Refreshed Periodically)                  │
│                                                                 │
│  ├─ coliseum_leaderboard_a_7d     (Cultural)                    │
│  ├─ coliseum_leaderboard_t_7d     (Behavioral)                  │
│  ├─ coliseum_leaderboard_g_7d     (Economic)                    │
│  ├─ coliseum_leaderboard_c_7d     (Spatial)                     │
│  └─ coliseum_leaderboard_total_7d (Overall)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 💡 Remaining Discussion Topics

1. **MediaID Access Pattern:** Option A (artist only), B (listener aggregate), or C (hybrid)?

2. **Vault Schema:** Can you share the Vault/Concierto table structures?

3. **Stripe Production Timeline:** When are we moving Stripe to production? (Determines G-Domain priority)

4. **CALS Launch Timeline:** When does CALS need to be operational? (Determines T-Domain enhancement priority)

5. **Leaderboard Opt-Out:** Should artists be able to opt out of public leaderboards (especially G-Domain)?

---

## 🎯 Success = Four Domains Operational

**When all four domains are integrated:**
- Artists see holistic DNA scores (A/T/G/C + Total)
- Leaderboards show cultural, behavioral, economic, and spatial rankings
- Coliseum becomes the authoritative artist analytics engine
- DNA system powers recommendations, discovery, and ecosystem insights
- Buckets differentiates from all other music platforms

**Philosophy:** "We are masters of pace" - each domain adds unique value, implement methodically

---

**Ready to start G-Domain implementation? Let me know what decisions you'd like to make first, or if you're ready to begin coding.**
