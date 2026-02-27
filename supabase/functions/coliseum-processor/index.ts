/**
 * ============================================================================
 * COLISEUM ANALYTICS - DNA MUTATION PROCESSOR
 * ============================================================================
 * Purpose: Background processor that consumes Passport events and calculates
 *          DNA domain strength (A/T/G/C) for artists, events, and users
 * Trigger: Scheduled (every 5 minutes) or manual invocation
 * ============================================================================
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// ============================================================================
// CONFIGURATION
// ============================================================================

const BATCH_SIZE = 100;
const MAX_RETRIES = 3;
const PROCESSING_TIMEOUT_MS = 300000; // 5 minutes

// ============================================================================
// TYPES
// ============================================================================

type DNADomain = 'A' | 'T' | 'G' | 'C';
type TimeRange = '7d' | '30d' | 'alltime';

interface PassportEvent {
  id: string;
  user_id: string;
  artist_id?: string;
  event_id?: string;
  entity_type?: string;
  entity_id?: string;
  event_type: string;
  event_category: string;
  timestamp?: string;
  created_at?: string;
  metadata: any;
}

interface DNAMutation {
  passport_entry_id: string;
  user_id: string;
  artist_id?: string;
  event_id?: string;
  domain: DNADomain;
  key: string;
  delta: number;
  weight: number;
  recency_decay: number;
  effective_delta: number;
  occurred_at: string;
}

// ============================================================================
// EVENT WEIGHTS & DECAY CONFIGS
// ============================================================================

const EVENT_WEIGHTS: Record<string, number> = {
  // TIER 5: Transformative
  'treasury.subscription_started': 1000,
  'concierto.event_hosted': 1000,
  'treasury.payout_received': 1000,
  'companon.campaign_launched': 1000,

  // TIER 4: High Intent
  'concierto.ticket_purchased': 100,
  'concierto.event_attended': 100,
  'concierto.vote_cast': 100,
  'locker.item_claimed': 100,
  'core.track_uploaded': 100,
  'companon.offer_redeemed': 100,

  // TIER 3: Moderate
  'concierto.event_rsvp': 10,
  'core.artist_followed': 10,
  'player.track_completed': 10,
  'locker.opened': 10,
  'companon.offer_viewed': 10,

  // TIER 2: Passive
  'player.track_played': 1,
  'core.track_viewed': 1,
  'concierto.event_viewed': 1,
  'companon.campaign_impression': 1,

  // TIER 1: Ambient
  'player.track_skipped': 0.1,
  'core.search_performed': 0.1,
  'navigation.page_viewed': 0.1,
};

const DECAY_CONFIGS: Record<string, { halfLifeDays: number; floor: number }> = {
  'player.track_played': { halfLifeDays: 7, floor: 0.1 },
  'player.track_skipped': { halfLifeDays: 7, floor: 0.1 },
  'concierto.event_viewed': { halfLifeDays: 7, floor: 0.1 },
  'core.artist_followed': { halfLifeDays: 30, floor: 0.3 },
  'concierto.vote_cast': { halfLifeDays: 30, floor: 0.3 },
  'concierto.ticket_purchased': { halfLifeDays: 90, floor: 0.5 },
  'treasury.subscription_started': { halfLifeDays: 180, floor: 0.7 },
  'concierto.event_attended': { halfLifeDays: 365, floor: 0.8 },
  'core.track_uploaded': { halfLifeDays: 365, floor: 0.9 },
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function calculateRecencyDecay(eventTimestamp: string, eventType: string): number {
  const config = DECAY_CONFIGS[eventType] || { halfLifeDays: 30, floor: 0.2 };
  const eventDate = new Date(eventTimestamp);
  const now = new Date();
  const daysSince = (now.getTime() - eventDate.getTime()) / (1000 * 60 * 60 * 24);
  const halfLives = daysSince / config.halfLifeDays;
  const rawDecay = Math.pow(0.5, halfLives);
  return Math.max(rawDecay, config.floor);
}

/**
 * Calculate event weight based on tier system and event metadata
 * 
 * TIER 1: 0.1   - Low value (skip, search)
 * TIER 2: 1.0   - Standard (play, view)
 * TIER 3: 10.0  - High value (like, save, repeat play, high completion)
 * TIER 4: 100.0 - Very high (purchase, tip, subscribe)
 * TIER 5: 1000.0 - Exceptional (superfan, high-value purchase)
 */
function getEventWeight(eventType: string, metadata: any = {}): number {
  const baseWeight = EVENT_WEIGHTS[eventType] || 1;
  
  // For audio plays, apply tiered weighting based on engagement
  if (eventType === 'player.track_played') {
    const progressPct = metadata.progress_percentage || 0;
    const isRepeatPlay = metadata.is_repeat_play || false;
    
    // TIER 3: High completion (>80%) or repeat play
    if (progressPct > 80 || isRepeatPlay) {
      return 10.0; // TIER 3
    }
    
    // TIER 2: Standard play (30-80% completion)
    if (progressPct >= 30) {
      return 1.0; // TIER 2
    }
    
    // TIER 1: Low engagement (<30% completion)
    return 0.1; // TIER 1
  }
  
  // For treasury events, apply amount-based weighting
  if (eventType === 'treasury.money_spent' || eventType.includes('purchase')) {
    const amountCents = metadata.amountCents || metadata.amount_cents || 0;
    
    // TIER 5: High-value purchases ($50+)
    if (amountCents >= 5000) {
      return 1000.0; // TIER 5
    }
    
    // TIER 4: Standard purchases
    if (amountCents > 0) {
      return 100.0; // TIER 4
    }
  }
  
  // Return base weight for other event types
  return baseWeight;
}

function getAdenineMultiplier(eventType: string): number {
  const multipliers: Record<string, number> = {
    'concierto.event_attended': 1.0,
    'concierto.ticket_purchased': 0.8,
    'concierto.vote_cast': 0.5,
    'core.artist_followed': 0.4,
    'player.track_completed': 0.3,
    'player.track_played': 0.1,
    'player.track_skipped': -0.05,
  };
  return multipliers[eventType] || 0.1;
}

function getThymineMultiplier(eventType: string, metadata: any): number {
  let baseMultiplier = 1.0;

  if (metadata.completion_pct) {
    baseMultiplier *= 1 + (metadata.completion_pct ** 2) * 2;
  }

  if (metadata.is_conversion) {
    baseMultiplier *= 3.0;
  }

  const typeMultipliers: Record<string, number> = {
    'concierto.event_attended': 1.0,
    'concierto.vote_cast': 0.8,
    'player.track_completed': 0.6,
    'concierto.ticket_purchased': 0.9,
    'player.track_played': 0.3,
  };

  return baseMultiplier * (typeMultipliers[eventType] || 0.5);
}

function getCytosineMultiplier(eventType: string): number {
  const multipliers: Record<string, number> = {
    'concierto.event_attended': 2.0,
    'concierto.ticket_purchased': 1.5,
    'concierto.event_rsvp': 0.8,
    'concierto.event_viewed': 0.3,
  };
  return multipliers[eventType] || 0.1;
}

// ============================================================================
// MUTATION GENERATION
// ============================================================================

/**
 * Extract artist_id from event using multiple fallback strategies
 */
function extractArtistId(event: PassportEvent): string | null {
  // Strategy 1: Direct artist_id field (if exists)
  if (event.artist_id) return event.artist_id;
  
  // Strategy 2: entity_id when entity_type is 'artist'
  if (event.entity_type === 'artist' && event.entity_id) {
    return event.entity_id;
  }
  
  // Strategy 3: metadata.artistId (camelCase)
  if (event.metadata?.artistId) return event.metadata.artistId;
  
  // Strategy 4: metadata.artist_id (snake_case)
  if (event.metadata?.artist_id) return event.metadata.artist_id;
  
  return null;
}

function generateMutations(event: PassportEvent): DNAMutation[] {
  const mutations: DNAMutation[] = [];
  const metadata = event.metadata || {};
  
  // Calculate weight based on event type AND metadata (tiered system)
  const baseWeight = getEventWeight(event.event_type, metadata);
  
  // Extract timestamp (support both timestamp and created_at columns)
  const eventTimestamp = event.timestamp || event.created_at || new Date().toISOString();
  const recencyDecay = calculateRecencyDecay(eventTimestamp, event.event_type);
  
  // Extract artist_id using fallback strategy
  const artistId = extractArtistId(event);
  
  // Skip events without artist_id (they can't generate mutations)
  if (!artistId) {
    console.warn(`[Coliseum] Skipping event ${event.id}: No artist_id found`);
    return [];
  }

  // Extract event_id (support both direct field and metadata)
  const eventId = event.event_id || metadata.eventId || metadata.event_id || null;
  
  // Log weight calculation for debugging
  if (event.event_type === 'player.track_played') {
    console.log(`[Coliseum] Event ${event.id}: weight=${baseWeight}, progress=${metadata.progress_percentage}%, repeat=${metadata.is_repeat_play}`);
  }

  // A-Domain: Cultural mutations (genre, interests)
  if (metadata.artist_genres && Array.isArray(metadata.artist_genres)) {
    for (const genre of metadata.artist_genres) {
      const delta = getAdenineMultiplier(event.event_type);
      mutations.push({
        passport_entry_id: event.id,
        user_id: event.user_id,
        artist_id: artistId,
        event_id: eventId,
        domain: 'A',
        key: genre,
        delta,
        weight: baseWeight,
        recency_decay: recencyDecay,
        effective_delta: delta * baseWeight * recencyDecay,
        occurred_at: eventTimestamp,
      });
    }
  }

  // T-Domain: Behavioral mutations (engagement, loyalty)
  // Always create T-domain mutation for engagement tracking
  const tDelta = getThymineMultiplier(event.event_type, metadata);
  mutations.push({
    passport_entry_id: event.id,
    user_id: event.user_id,
    artist_id: artistId,
    event_id: eventId,
    domain: 'T',
    key: 'engagement',
    delta: tDelta,
    weight: baseWeight,
    recency_decay: recencyDecay,
    effective_delta: tDelta * baseWeight * recencyDecay,
    occurred_at: eventTimestamp,
  });

  // G-Domain: Economic mutations (revenue, transactions)
  if (
    metadata.amount_cents ||
    metadata.amountCents ||
    event.event_type.includes('purchase') ||
    event.event_type.includes('payout') ||
    event.event_type.includes('treasury.money_spent')
  ) {
    const amountCents = metadata.amount_cents || metadata.amountCents || 0;
    const gDelta = amountCents / 100; // Cents to dollars
    mutations.push({
      passport_entry_id: event.id,
      user_id: event.user_id,
      artist_id: artistId,
      event_id: eventId,
      domain: 'G',
      key: 'revenue',
      delta: gDelta,
      weight: baseWeight,
      recency_decay: recencyDecay,
      effective_delta: gDelta * baseWeight * recencyDecay,
      occurred_at: eventTimestamp,
    });
  }

  // C-Domain: Spatial mutations (city, location)
  if (metadata.city || metadata.location_city) {
    const city = metadata.city || metadata.location_city;
    const cDelta = getCytosineMultiplier(event.event_type);
    mutations.push({
      passport_entry_id: event.id,
      user_id: event.user_id,
      artist_id: artistId,
      event_id: eventId,
      domain: 'C',
      key: `city:${city}`,
      delta: cDelta,
      weight: baseWeight,
      recency_decay: recencyDecay,
      effective_delta: cDelta * baseWeight * recencyDecay,
      occurred_at: eventTimestamp,
    });
  }

  return mutations;
}

// ============================================================================
// MAIN PROCESSOR
// ============================================================================

serve(async (req) => {
  const startTime = Date.now();

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    console.log('[Coliseum Processor] Starting batch processing...');

    // 1. Fetch unprocessed Passport events
    // Select both timestamp and created_at to handle schema variations
    const { data: events, error: fetchError } = await supabase
      .from('passport_entries')
      .select('*')
      .is('coliseum_processed_at', null)
      .order('created_at', { ascending: true })
      .limit(BATCH_SIZE);

    if (fetchError) {
      console.error('[Coliseum Processor] Fetch error:', fetchError);
      throw fetchError;
    }

    if (!events || events.length === 0) {
      console.log('[Coliseum Processor] No events to process');
      return new Response(
        JSON.stringify({ success: true, processed: 0, message: 'No events to process' }),
        { headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[Coliseum Processor] Processing ${events.length} events`);

    // 2. Generate DNA mutations from events
    const allMutations: DNAMutation[] = [];
    for (const event of events) {
      const mutations = generateMutations(event as PassportEvent);
      allMutations.push(...mutations);
    }

    console.log(`[Coliseum Processor] Generated ${allMutations.length} DNA mutations`);

    // 3. Insert mutations into coliseum_dna_mutations table (idempotent)
    if (allMutations.length > 0) {
      const { error: insertError } = await supabase
        .from('coliseum_dna_mutations')
        .upsert(allMutations, { onConflict: 'passport_entry_id' });

      if (insertError) {
        console.error('[Coliseum Processor] Insert mutations error:', insertError);
        throw insertError;
      }
    }

    // 4. Mark Passport events as processed
    const eventIds = events.map((e) => e.id);
    const { error: updateError } = await supabase
      .from('passport_entries')
      .update({ coliseum_processed_at: new Date().toISOString() })
      .in('id', eventIds);

    if (updateError) {
      console.error('[Coliseum Processor] Update error:', updateError);
      throw updateError;
    }

    // 5. Recalculate domain strength for affected artists
    const affectedArtists = new Set<string>();
    for (const event of events) {
      const artistId = extractArtistId(event as PassportEvent);
      if (artistId) {
        affectedArtists.add(artistId);
      }
    }

    console.log(`[Coliseum Processor] Recalculating domain strength for ${affectedArtists.size} artists`);

    for (const artistId of affectedArtists) {
      try {
        await recalculateDomainStrength(supabase, artistId, '7d');
        await recalculateDomainStrength(supabase, artistId, '30d');
        await recalculateDomainStrength(supabase, artistId, 'alltime');
      } catch (err) {
        console.error(`[Coliseum Processor] Failed to recalculate artist ${artistId}:`, err);
        // Continue processing other artists
      }
    }

    // 6. Refresh materialized views (if time permits)
    const elapsedTime = Date.now() - startTime;
    if (elapsedTime < PROCESSING_TIMEOUT_MS - 30000) {
      // Leave 30s buffer
      console.log('[Coliseum Processor] Refreshing materialized views...');
      try {
        await supabase.rpc('refresh_coliseum_leaderboards', { p_time_range: '7d' });
      } catch (err) {
        console.error('[Coliseum Processor] Refresh views error:', err);
        // Non-critical, continue
      }
    }

    const totalTime = Date.now() - startTime;
    console.log(`[Coliseum Processor] ✓ Completed in ${totalTime}ms`);

    return new Response(
      JSON.stringify({
        success: true,
        processed: events.length,
        mutations_generated: allMutations.length,
        artists_recalculated: affectedArtists.size,
        processing_time_ms: totalTime,
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    console.error('[Coliseum Processor] Fatal error:', error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        stack: error.stack,
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
});

// ============================================================================
// DOMAIN STRENGTH RECALCULATION
// ============================================================================

async function recalculateDomainStrength(
  supabase: any,
  artistId: string,
  timeRange: TimeRange
): Promise<void> {
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
    case 'alltime':
      sinceDate = new Date(0);
      break;
  }

  // Fetch all mutations for this artist in time range
  const { data: mutations, error } = await supabase
    .from('coliseum_dna_mutations')
    .select('*')
    .eq('artist_id', artistId)
    .gte('occurred_at', sinceDate.toISOString());

  if (error) throw error;

  // Aggregate by domain
  const domainTotals = {
    A: 0,
    T: 0,
    G: 0,
    C: 0,
  };

  const domainDetails: any = {
    A: { genres: {} },
    T: { events: [] },
    G: { revenue: 0, transactions: 0 },
    C: { cities: {} },
  };

  for (const mutation of mutations || []) {
    domainTotals[mutation.domain as DNADomain] += mutation.effective_delta;

    // Collect metadata
    if (mutation.domain === 'A') {
      domainDetails.A.genres[mutation.key] =
        (domainDetails.A.genres[mutation.key] || 0) + mutation.effective_delta;
    } else if (mutation.domain === 'C' && mutation.key.startsWith('city:')) {
      const city = mutation.key.replace('city:', '');
      domainDetails.C.cities[city] =
        (domainDetails.C.cities[city] || 0) + mutation.effective_delta;
    } else if (mutation.domain === 'G') {
      domainDetails.G.revenue += mutation.effective_delta;
      domainDetails.G.transactions++;
    }
  }

  // Calculate metadata
  const a_metadata = {
    genre_diversity_index: calculateGenreDiversity(domainDetails.A.genres),
    primary_genres: Object.keys(domainDetails.A.genres)
      .sort((a, b) => domainDetails.A.genres[b] - domainDetails.A.genres[a])
      .slice(0, 3),
    crossover_potential: calculateGenreDiversity(domainDetails.A.genres), // Same as diversity
    niche_depth: 1 - calculateGenreDiversity(domainDetails.A.genres),
    genre_engagement: domainDetails.A.genres,
  };

  const t_metadata = {
    loyalty_index: 0.5, // Placeholder - needs full calculation
    conversion_rate: 0.5,
    superfan_percentage: 0.1,
    engagement_consistency: 0.7,
    activation_rate: 0.6,
    churn_risk_score: 0.3,
    avg_interactions_per_fan: 5,
  };

  const g_metadata = {
    avg_transaction_value: domainDetails.G.transactions > 0 ? domainDetails.G.revenue / domainDetails.G.transactions : 0,
    willingness_to_pay_index: 0.5,
    revenue_concentration: 0.5,
    lifetime_value_per_fan: domainDetails.G.revenue,
    monetization_efficiency: domainDetails.G.revenue / Math.max(1, mutations?.length || 1),
    whale_fan_count: 0,
    total_revenue_cents: domainDetails.G.revenue * 100,
  };

  const c_metadata = {
    primary_cities: Object.keys(domainDetails.C.cities)
      .sort((a, b) => domainDetails.C.cities[b] - domainDetails.C.cities[a])
      .slice(0, 5),
    geographic_reach_index: Math.min(Object.keys(domainDetails.C.cities).length / 100, 1),
    touring_viability_score: Math.min(Object.values(domainDetails.C.cities).filter((v: any) => v >= 50).length / 5, 1),
    city_to_city_mobility: Object.keys(domainDetails.C.cities).length > 1 ? 0.5 : 0,
    market_penetration_top_city: 0.1,
    expansion_velocity: Object.keys(domainDetails.C.cities).length / 6,
    city_engagement: domainDetails.C.cities,
  };

  // Upsert domain strength
  const { error: upsertError } = await supabase.from('coliseum_domain_strength').upsert(
    {
      entity_id: artistId,
      entity_type: 'artist',
      time_range: timeRange,
      a_strength: domainTotals.A,
      t_strength: domainTotals.T,
      g_strength: domainTotals.G,
      c_strength: domainTotals.C,
      a_metadata,
      t_metadata,
      g_metadata,
      c_metadata,
      calculated_at: new Date().toISOString(),
    },
    { onConflict: 'entity_id,entity_type,time_range' }
  );

  if (upsertError) throw upsertError;
}

function calculateGenreDiversity(genres: Record<string, number>): number {
  const values = Object.values(genres);
  const total = values.reduce((a, b) => a + b, 0);
  if (total === 0) return 0;

  const probabilities = values.map((v) => v / total);
  let entropy = 0;
  for (const p of probabilities) {
    if (p > 0) {
      entropy -= p * Math.log2(p);
    }
  }

  const maxEntropy = Math.log2(Object.keys(genres).length || 1);
  return maxEntropy > 0 ? entropy / maxEntropy : 0;
}
