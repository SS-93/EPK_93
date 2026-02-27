# Coliseum Analytics Engine - Next Steps & Action Items

**Date:** February 3, 2026  
**Status:** Implementation Review Complete

---

## 🎯 Current State Summary

### ✅ What's Working
- **Edge Function**: `coliseum-processor/index.ts` is fully implemented
- **Event Integration**: Passport events are being logged with `processed_by_coliseum: false` flag
- **Treasury Integration**: Revenue events (`treasury.money_spent`) are being logged correctly
- **Mutation Logic**: DNA mutation generation logic is complete and well-structured

### ⚠️ What's Missing
- **Database Tables**: Coliseum tables (`coliseum_dna_mutations`, `coliseum_domain_strength`) not found in migrations
- **Scheduled Execution**: No cron job configured to run the processor
- **API Endpoints**: No endpoints to query domain strength or leaderboards
- **Database Column**: `coliseum_processed_at` column may be missing from `passport_entries`

---

## 📋 Priority Action Items

### Priority 1: Database Setup (CRITICAL)

#### 1.1 Create Database Migration
Create a new migration file: `supabase/migrations/YYYYMMDDHHMMSS_create_coliseum_tables.sql`

```sql
-- ===============================================
-- COLISEUM ANALYTICS - Database Schema
-- ===============================================

-- Add coliseum processing column to passport_entries if missing
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'passport_entries' 
    AND column_name = 'coliseum_processed_at'
  ) THEN
    ALTER TABLE passport_entries 
    ADD COLUMN coliseum_processed_at TIMESTAMP;
  END IF;
END $$;

-- Create DNA mutations table
CREATE TABLE IF NOT EXISTS coliseum_dna_mutations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  passport_entry_id UUID NOT NULL,
  user_id UUID NOT NULL,
  artist_id UUID,
  event_id UUID,
  domain TEXT NOT NULL CHECK (domain IN ('A', 'T', 'G', 'C')),
  key TEXT NOT NULL,
  delta NUMERIC NOT NULL,
  weight NUMERIC NOT NULL,
  recency_decay NUMERIC NOT NULL,
  effective_delta NUMERIC NOT NULL,
  occurred_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT now(),
  UNIQUE(passport_entry_id, domain, key)
);

-- Create domain strength table
CREATE TABLE IF NOT EXISTS coliseum_domain_strength (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id UUID NOT NULL,
  entity_type TEXT DEFAULT 'artist',
  time_range TEXT NOT NULL CHECK (time_range IN ('7d', '30d', 'alltime')),
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

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_passport_coliseum_unprocessed 
  ON passport_entries(coliseum_processed_at) 
  WHERE coliseum_processed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_mutations_artist_time 
  ON coliseum_dna_mutations(artist_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_mutations_user_time 
  ON coliseum_dna_mutations(user_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_domain_strength_lookup 
  ON coliseum_domain_strength(entity_id, entity_type, time_range);

CREATE INDEX IF NOT EXISTS idx_domain_strength_time_range 
  ON coliseum_domain_strength(time_range, entity_type);

-- Add foreign key constraints
ALTER TABLE coliseum_dna_mutations
  ADD CONSTRAINT fk_passport_entry 
  FOREIGN KEY (passport_entry_id) 
  REFERENCES passport_entries(id) 
  ON DELETE CASCADE;

-- Grant permissions (adjust based on your RLS setup)
-- Note: RLS policies should be added separately
```

#### 1.2 Verify passport_entries Table Structure
Check if `passport_entries` table exists and has required columns:

```sql
-- Run this query to check table structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'passport_entries'
ORDER BY ordinal_position;
```

Required columns:
- `id` (UUID)
- `user_id` (UUID)
- `artist_id` (UUID, nullable)
- `event_id` (UUID, nullable)
- `event_type` (TEXT)
- `event_category` (TEXT)
- `timestamp` (TIMESTAMP)
- `metadata` (JSONB)
- `processed_by_coliseum` (BOOLEAN)
- `coliseum_processed_at` (TIMESTAMP, nullable)

#### 1.3 Apply Migration
```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
supabase migration up
# OR if using local Supabase:
supabase db reset  # (careful - this resets local DB)
```

---

### Priority 2: Scheduled Execution (CRITICAL)

#### 2.1 Option A: Supabase Cron (Recommended)
Create a cron job in Supabase Dashboard:
1. Go to Database → Cron Jobs
2. Create new cron job:
   - **Name**: `coliseum-processor`
   - **Schedule**: `*/5 * * * *` (every 5 minutes)
   - **SQL Command**:
     ```sql
     SELECT net.http_post(
       url := 'https://<your-project-ref>.supabase.co/functions/v1/coliseum-processor',
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
       ),
       body := '{}'::jsonb
     );
     ```

#### 2.2 Option B: External Cron Service
Use a service like:
- **GitHub Actions** (if repo is on GitHub)
- **Vercel Cron** (if using Vercel)
- **Cloudflare Workers Cron** (free tier available)
- **AWS EventBridge** (if on AWS)

Example GitHub Actions workflow (`.github/workflows/coliseum-processor.yml`):
```yaml
name: Coliseum Processor

on:
  schedule:
    - cron: '*/5 * * * *'  # Every 5 minutes
  workflow_dispatch:  # Manual trigger

jobs:
  process:
    runs-on: ubuntu-latest
    steps:
      - name: Invoke Coliseum Processor
        run: |
          curl -X POST \
            -H "Authorization: Bearer ${{ secrets.SUPABASE_SERVICE_ROLE_KEY }}" \
            -H "Content-Type: application/json" \
            https://<your-project-ref>.supabase.co/functions/v1/coliseum-processor
```

#### 2.3 Option C: Manual Testing
For immediate testing, invoke manually:
```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  https://<your-project-ref>.supabase.co/functions/v1/coliseum-processor
```

---

### Priority 3: API Endpoints (HIGH)

#### 3.1 Create Coliseum Routes File
Create `Routes/coliseum.ts`:

```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

export const coliseumRoutes = {
  /**
   * GET /coliseum/artist/:artistId/strength
   * Get domain strength for an artist
   */
  async getArtistStrength(req: Request, artistId: string): Promise<Response> {
    const url = new URL(req.url);
    const timeRange = url.searchParams.get('time_range') || '7d';
    
    if (!['7d', '30d', 'alltime'].includes(timeRange)) {
      return new Response(
        JSON.stringify({ error: 'Invalid time_range' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const { data, error } = await supabase
      .from('coliseum_domain_strength')
      .select('*')
      .eq('entity_id', artistId)
      .eq('entity_type', 'artist')
      .eq('time_range', timeRange)
      .single();

    if (error) {
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          artist_id: artistId,
          time_range: timeRange,
          domains: {
            A: { strength: data.a_strength, metadata: data.a_metadata },
            T: { strength: data.t_strength, metadata: data.t_metadata },
            G: { strength: data.g_strength, metadata: data.g_metadata },
            C: { strength: data.c_strength, metadata: data.c_metadata },
          },
          calculated_at: data.calculated_at,
        },
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  },

  /**
   * GET /coliseum/leaderboard
   * Get leaderboard for a domain
   */
  async getLeaderboard(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const timeRange = url.searchParams.get('time_range') || '7d';
    const domain = url.searchParams.get('domain') || 'G';
    const limit = parseInt(url.searchParams.get('limit') || '100');

    if (!['A', 'T', 'G', 'C'].includes(domain)) {
      return new Response(
        JSON.stringify({ error: 'Invalid domain' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const strengthColumn = `${domain.toLowerCase()}_strength`;

    const { data, error } = await supabase
      .from('coliseum_domain_strength')
      .select('entity_id, ' + strengthColumn)
      .eq('entity_type', 'artist')
      .eq('time_range', timeRange)
      .order(strengthColumn, { ascending: false })
      .limit(limit);

    if (error) {
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    const artists = data.map((row, index) => ({
      artist_id: row.entity_id,
      strength: row[strengthColumn],
      rank: index + 1,
    }));

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          time_range: timeRange,
          domain,
          artists,
        },
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  },

  /**
   * GET /coliseum/mutations/:artistId
   * Get recent mutations for an artist
   */
  async getMutations(req: Request, artistId: string): Promise<Response> {
    const url = new URL(req.url);
    const timeRange = url.searchParams.get('time_range') || '30d';
    const limit = parseInt(url.searchParams.get('limit') || '100');

    // Calculate date threshold
    const now = new Date();
    let sinceDate: Date;
    switch (timeRange) {
      case '7d':
        sinceDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
        break;
      case '30d':
        sinceDate = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
        break;
      default:
        sinceDate = new Date(0);
    }

    const { data, error } = await supabase
      .from('coliseum_dna_mutations')
      .select('*')
      .eq('artist_id', artistId)
      .gte('occurred_at', sinceDate.toISOString())
      .order('occurred_at', { ascending: false })
      .limit(limit);

    if (error) {
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          artist_id: artistId,
          time_range: timeRange,
          mutations: data,
        },
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  },
};
```

#### 3.2 Add Routes to Router
Update `api/router.ts`:

```typescript
import { coliseumRoutes } from '../Routes/coliseum.ts'

// Add to routes object:
const routes: { [key: string]: RouteHandler } = {
  '/auth': authRoutes,
  '/subscriptions': subscriptionRoutes,
  '/mediaid': mediaIdRoutes,
  '/content': contentRoutes,
  '/stripe': stripeRoutes,
  '/coliseum': coliseumRoutes,  // Add this
}

// Add routing function:
async function routeColiseum(req: Request, method: string, subPath: string): Promise<Response> {
  const parts = subPath.split('/');
  
  if (parts[0] === 'artist' && parts.length === 3 && parts[2] === 'strength') {
    return coliseumRoutes.getArtistStrength(req, parts[1]);
  }
  
  if (parts[0] === 'leaderboard') {
    return coliseumRoutes.getLeaderboard(req);
  }
  
  if (parts[0] === 'mutations' && parts.length === 2) {
    return coliseumRoutes.getMutations(req, parts[1]);
  }
  
  return createNotFoundResponse('Coliseum endpoint');
}
```

---

### Priority 4: Testing & Validation (MEDIUM)

#### 4.1 Test Event Processing
1. Create test events via Passport API:
   ```bash
   curl -X POST http://localhost:8000/api/passport/events \
     -H "Content-Type: application/json" \
     -d '{
       "userId": "test-user-id",
       "type": "treasury.money_spent",
       "payload": {
         "artistId": "test-artist-id",
         "amountCents": 1000,
         "reason": "ticket"
       }
     }'
   ```

2. Manually trigger processor:
   ```bash
   curl -X POST \
     -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
     https://<project-ref>.supabase.co/functions/v1/coliseum-processor
   ```

3. Verify mutations were created:
   ```sql
   SELECT * FROM coliseum_dna_mutations 
   WHERE artist_id = 'test-artist-id' 
   ORDER BY occurred_at DESC 
   LIMIT 10;
   ```

4. Verify domain strength was calculated:
   ```sql
   SELECT * FROM coliseum_domain_strength 
   WHERE entity_id = 'test-artist-id';
   ```

#### 4.2 Test API Endpoints
```bash
# Get artist strength
curl http://localhost:8000/api/coliseum/artist/test-artist-id/strength?time_range=7d

# Get leaderboard
curl http://localhost:8000/api/coliseum/leaderboard?domain=G&time_range=7d

# Get mutations
curl http://localhost:8000/api/coliseum/mutations/test-artist-id?time_range=30d
```

---

### Priority 5: Monitoring & Observability (LOW)

#### 5.1 Add Logging
Update `coliseum-processor/index.ts` to include more detailed logging:
- Processing start/end times
- Events processed count
- Mutations generated count
- Artists recalculated
- Errors with context

#### 5.2 Create Monitoring Dashboard
Track:
- Unprocessed event backlog
- Processing time trends
- Domain strength distribution
- Top artists by domain

#### 5.3 Set Up Alerts
- Alert if backlog exceeds 1000 events
- Alert if processing time exceeds 4 minutes
- Alert on processor failures

---

## 🔍 Verification Checklist

Before considering Coliseum complete, verify:

- [ ] Database tables created (`coliseum_dna_mutations`, `coliseum_domain_strength`)
- [ ] `coliseum_processed_at` column exists in `passport_entries`
- [ ] Indexes created for performance
- [ ] Edge function deployed successfully
- [ ] Scheduled execution configured (cron job)
- [ ] API endpoints implemented and tested
- [ ] Test events processed successfully
- [ ] Domain strength calculations verified
- [ ] Leaderboard queries working
- [ ] Error handling tested
- [ ] Documentation updated

---

## 📚 Additional Resources

- **Full Review**: See `COLISEUM_ANALYTICS_REVIEW.md`
- **Edge Function**: `supabase/functions/coliseum-processor/index.ts`
- **Integration**: `server.js` (lines 320-392, 467-515, 855-874)
- **Supabase Docs**: https://supabase.com/docs/guides/functions

---

## 🚀 Quick Start Commands

```bash
# 1. Create migration
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
supabase migration new create_coliseum_tables

# 2. Add SQL to migration file (see Priority 1.1)

# 3. Apply migration
supabase migration up

# 4. Deploy edge function
supabase functions deploy coliseum-processor

# 5. Test manually
curl -X POST \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  https://<project-ref>.supabase.co/functions/v1/coliseum-processor

# 6. Check results
supabase db query "SELECT COUNT(*) FROM coliseum_dna_mutations;"
```

---

**Next Review Date**: After Priority 1-3 items completed
