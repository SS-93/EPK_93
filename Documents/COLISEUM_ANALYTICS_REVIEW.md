# Coliseum Analytics Engine - Codebase Review

**Date:** February 3, 2026  
**Project:** Buckets.MVP  
**Focus:** Coliseum Analytics Engine Implementation

---

## Executive Summary

The **Coliseum Analytics Engine** is a DNA mutation processor that transforms user interaction events (Passport entries) into actionable analytics for artists. It calculates domain strength across four DNA domains (A/T/G/C) representing different aspects of artist performance: Cultural (A), Behavioral (T), Economic (G), and Spatial (C).

### Current Status: ✅ **Partially Implemented**

- ✅ Edge Function processor exists (`coliseum-processor/index.ts`)
- ✅ Integration with Passport event logging in `server.js`
- ⚠️ Database schema for coliseum tables needs verification
- ⚠️ Scheduled execution not configured
- ⚠️ API endpoints for querying analytics not implemented

---

## Architecture Overview

### 1. Data Flow

```
User Actions → Passport Events → Coliseum Processor → DNA Mutations → Domain Strength
```

1. **Event Ingestion**: User interactions logged to `passport_entries` table via `/api/passport/events` endpoint
2. **Batch Processing**: Coliseum processor runs periodically (every 5 minutes) to process unprocessed events
3. **Mutation Generation**: Each event generates DNA mutations across relevant domains
4. **Strength Calculation**: Mutations aggregated to calculate domain strength per artist
5. **Analytics Storage**: Results stored in `coliseum_domain_strength` table

### 2. Core Components

#### A. Passport Event System (`server.js`)
- **Endpoint**: `POST /api/passport/events`
- **Purpose**: Fast event logging (<50ms response time requirement)
- **Integration**: Sets `processed_by_coliseum: false` flag on new events
- **Key Events Logged**:
  - `treasury.money_spent` (for G-domain revenue tracking)
  - `concierto.ticket_purchased`
  - `concierto.event_attended`
  - `player.track_played`
  - And 20+ other event types

#### B. Coliseum Processor (`supabase/functions/coliseum-processor/index.ts`)
- **Type**: Supabase Edge Function (Deno runtime)
- **Trigger**: Scheduled (every 5 minutes) or manual invocation
- **Batch Size**: 100 events per run
- **Processing Steps**:
  1. Fetch unprocessed Passport events (`coliseum_processed_at IS NULL`)
  2. Generate DNA mutations for each event
  3. Insert mutations into `coliseum_dna_mutations` table
  4. Mark events as processed
  5. Recalculate domain strength for affected artists
  6. Refresh materialized views (if time permits)

#### C. DNA Domain System

**A-Domain (Adenine) - Cultural Mutations**
- **Purpose**: Genre preferences and cultural interests
- **Sources**: Artist genres from event metadata
- **Multipliers**: Event attendance (1.0x), ticket purchase (0.8x), votes (0.5x)
- **Metadata**: Genre diversity index, primary genres, crossover potential

**T-Domain (Thymine) - Behavioral Mutations**
- **Purpose**: Engagement depth and loyalty
- **Sources**: Completion percentages, conversion flags, interaction types
- **Multipliers**: Completion % squared, conversion flag (3.0x)
- **Metadata**: Loyalty index, conversion rate, superfan percentage, churn risk

**G-Domain (Guanine) - Economic Mutations**
- **Purpose**: Revenue and transaction tracking
- **Sources**: `treasury.money_spent` events, purchase amounts
- **Calculation**: Amount in cents / 100 (converted to dollars)
- **Metadata**: Avg transaction value, willingness to pay, lifetime value per fan

**C-Domain (Cytosine) - Spatial Mutations**
- **Purpose**: Geographic distribution and touring viability
- **Sources**: City metadata from events
- **Multipliers**: Event attendance (2.0x), ticket purchase (1.5x), RSVP (0.8x)
- **Metadata**: Primary cities, geographic reach index, touring viability score

---

## Database Schema Requirements

### Required Tables

#### 1. `passport_entries` (Base Event Table)
```sql
-- Must include:
- id (UUID)
- user_id (UUID)
- artist_id (UUID, nullable)
- event_id (UUID, nullable)
- event_type (TEXT)
- event_category (TEXT)
- timestamp (TIMESTAMP)
- metadata (JSONB)
- processed_by_coliseum (BOOLEAN, default false)
- coliseum_processed_at (TIMESTAMP, nullable)
```

#### 2. `coliseum_dna_mutations` (Mutation Storage)
```sql
CREATE TABLE coliseum_dna_mutations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  passport_entry_id UUID REFERENCES passport_entries(id),
  user_id UUID NOT NULL,
  artist_id UUID,
  event_id UUID,
  domain TEXT CHECK (domain IN ('A', 'T', 'G', 'C')),
  key TEXT NOT NULL,  -- e.g., genre name, 'engagement', 'revenue', 'city:NewYork'
  delta NUMERIC NOT NULL,
  weight NUMERIC NOT NULL,
  recency_decay NUMERIC NOT NULL,
  effective_delta NUMERIC NOT NULL,  -- delta * weight * recency_decay
  occurred_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT now(),
  UNIQUE(passport_entry_id, domain, key)
);
```

#### 3. `coliseum_domain_strength` (Analytics Results)
```sql
CREATE TABLE coliseum_domain_strength (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id UUID NOT NULL,  -- artist_id
  entity_type TEXT DEFAULT 'artist',
  time_range TEXT CHECK (time_range IN ('7d', '30d', 'alltime')),
  a_strength NUMERIC DEFAULT 0,
  t_strength NUMERIC DEFAULT 0,
  g_strength NUMERIC DEFAULT 0,
  c_strength NUMERIC DEFAULT 0,
  a_metadata JSONB DEFAULT '{}',
  t_metadata JSONB DEFAULT '{}',
  g_metadata JSONB DEFAULT '{}',
  c_metadata JSONB DEFAULT '{}',
  calculated_at TIMESTAMP DEFAULT now(),
  UNIQUE(entity_id, entity_type, time_range)
);
```

#### 4. Materialized Views (Leaderboards)
```sql
-- Function to refresh leaderboards
CREATE OR REPLACE FUNCTION refresh_coliseum_leaderboards(p_time_range TEXT)
RETURNS void AS $$
-- Implementation needed for leaderboard views
$$ LANGUAGE plpgsql;
```

---

## Event Weight System

### Tier 5: Transformative (Weight: 1000)
- `treasury.subscription_started`
- `concierto.event_hosted`
- `treasury.payout_received`
- `companon.campaign_launched`

### Tier 4: High Intent (Weight: 100)
- `concierto.ticket_purchased`
- `concierto.event_attended`
- `concierto.vote_cast`
- `locker.item_claimed`
- `core.track_uploaded`
- `companon.offer_redeemed`

### Tier 3: Moderate (Weight: 10)
- `concierto.event_rsvp`
- `core.artist_followed`
- `player.track_completed`
- `locker.opened`
- `companon.offer_viewed`

### Tier 2: Passive (Weight: 1)
- `player.track_played`
- `core.track_viewed`
- `concierto.event_viewed`
- `companon.campaign_impression`

### Tier 1: Ambient (Weight: 0.1)
- `player.track_skipped`
- `core.search_performed`
- `navigation.page_viewed`

---

## Recency Decay Configuration

Events decay over time based on half-life periods:

| Event Type | Half-Life | Floor |
|------------|-----------|-------|
| `player.track_played` | 7 days | 0.1 |
| `concierto.event_viewed` | 7 days | 0.1 |
| `core.artist_followed` | 30 days | 0.3 |
| `concierto.vote_cast` | 30 days | 0.3 |
| `concierto.ticket_purchased` | 90 days | 0.5 |
| `treasury.subscription_started` | 180 days | 0.7 |
| `concierto.event_attended` | 365 days | 0.8 |
| `core.track_uploaded` | 365 days | 0.9 |

**Formula**: `decay = max(0.5^(days_since_event / half_life_days), floor)`

---

## Integration Points

### 1. Treasury Integration (`server.js:467-515`)
- Logs `treasury.money_spent` events after successful purchases
- Attributes revenue to artists via `event_artist_prospects` table
- Required metadata:
  - `artistId` (required for Coliseum)
  - `amountCents` (gross amount before splits)
  - `reason` (ticket | tip | subscription)
  - `eventId` (if event-related)

### 2. Passport Stats Endpoint (`server.js:369-392`)
- `GET /api/passport/stats`
- Returns total entries and unprocessed count
- Useful for monitoring processor backlog

---

## Configuration & Deployment

### Environment Variables Required
```bash
SUPABASE_URL=<your-project-url>
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
```

### Deployment Steps

1. **Deploy Edge Function**:
   ```bash
   supabase functions deploy coliseum-processor
   ```

2. **Set Up Scheduled Execution**:
   - Configure Supabase cron job or external scheduler
   - Target: `https://<project-ref>.supabase.co/functions/v1/coliseum-processor`
   - Frequency: Every 5 minutes
   - Method: POST

3. **Create Database Tables**:
   - Run migration to create `coliseum_dna_mutations`
   - Run migration to create `coliseum_domain_strength`
   - Add `coliseum_processed_at` column to `passport_entries` if missing

4. **Create Indexes**:
   ```sql
   CREATE INDEX idx_passport_coliseum_unprocessed 
     ON passport_entries(coliseum_processed_at) 
     WHERE coliseum_processed_at IS NULL;
   
   CREATE INDEX idx_mutations_artist_time 
     ON coliseum_dna_mutations(artist_id, occurred_at);
   
   CREATE INDEX idx_domain_strength_lookup 
     ON coliseum_domain_strength(entity_id, entity_type, time_range);
   ```

---

## API Endpoints Needed

### Query Analytics

#### `GET /api/coliseum/artist/:artistId/strength`
```json
{
  "time_range": "7d" | "30d" | "alltime",
  "domains": {
    "A": { "strength": 1250.5, "metadata": {...} },
    "T": { "strength": 890.2, "metadata": {...} },
    "G": { "strength": 5000.0, "metadata": {...} },
    "C": { "strength": 320.1, "metadata": {...} }
  }
}
```

#### `GET /api/coliseum/leaderboard`
```json
{
  "time_range": "7d",
  "domain": "G",  // A, T, G, or C
  "limit": 100,
  "artists": [
    { "artist_id": "...", "strength": 5000, "rank": 1 },
    ...
  ]
}
```

#### `GET /api/coliseum/mutations/:artistId`
```json
{
  "time_range": "30d",
  "mutations": [
    {
      "domain": "G",
      "key": "revenue",
      "effective_delta": 50.0,
      "occurred_at": "2026-01-15T10:30:00Z"
    },
    ...
  ]
}
```

---

## Known Issues & Recommendations

### ⚠️ Issues Identified

1. **Missing Database Schema**
   - Coliseum tables not found in main schema file
   - Need to verify/create tables before deployment

2. **No Scheduled Execution**
   - Processor function exists but no cron configuration found
   - Need to set up Supabase cron or external scheduler

3. **Missing API Endpoints**
   - No endpoints to query domain strength or leaderboards
   - Frontend cannot access analytics data

4. **Incomplete Metadata Calculations**
   - T-domain metadata has placeholder values (loyalty_index: 0.5)
   - Need full implementation of loyalty and churn calculations

5. **No Error Recovery**
   - Failed mutations don't have retry logic
   - Consider adding dead-letter queue for failed events

### ✅ Recommendations

1. **Immediate Actions**:
   - Create database migration for coliseum tables
   - Add API routes for querying analytics
   - Set up scheduled execution
   - Add monitoring/logging for processor runs

2. **Short-term Improvements**:
   - Implement full T-domain metadata calculations
   - Add materialized views for leaderboards
   - Create admin dashboard for monitoring
   - Add unit tests for mutation generation logic

3. **Long-term Enhancements**:
   - Real-time domain strength updates (via triggers)
   - Predictive analytics (churn risk, revenue forecasting)
   - Cross-artist comparisons and benchmarking
   - Export capabilities for external analytics tools

---

## Testing Strategy

### Unit Tests Needed
- Mutation generation for each event type
- Recency decay calculations
- Domain strength aggregation
- Genre diversity index calculation

### Integration Tests Needed
- End-to-end event processing flow
- Batch processing with large event sets
- Concurrent processing scenarios
- Error handling and recovery

### Performance Tests Needed
- Processor throughput (events/second)
- Database query performance
- Leaderboard refresh time
- API response times

---

## Monitoring & Observability

### Key Metrics to Track
- Events processed per batch
- Processing time per batch
- Backlog size (unprocessed events)
- Domain strength calculation time
- API endpoint latency
- Error rates

### Logging Points
- Batch start/completion
- Mutation generation counts
- Artist recalculation triggers
- Error conditions
- Performance bottlenecks

---

## Documentation Gaps

1. **Missing Documentation**:
   - Database schema documentation
   - API endpoint specifications
   - Deployment guide
   - Troubleshooting guide
   - Domain strength interpretation guide

2. **Incomplete Documentation**:
   - Event type catalog (need full list)
   - Metadata structure definitions
   - Leaderboard calculation logic

---

## Conclusion

The Coliseum Analytics Engine is a sophisticated system for transforming user interactions into actionable artist analytics. The core processor is well-designed and implements a thoughtful DNA domain model. However, several critical components are missing or incomplete:

**Priority 1 (Critical)**:
- Database schema creation
- Scheduled execution setup
- Basic API endpoints for querying results

**Priority 2 (Important)**:
- Complete metadata calculations
- Leaderboard views
- Error handling improvements

**Priority 3 (Enhancement)**:
- Real-time updates
- Advanced analytics features
- Comprehensive testing

The foundation is solid, but deployment readiness requires addressing the critical gaps identified above.
