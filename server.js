/**
 * Express Server for Buckets Backend
 * Handles Stripe payments and API routes
 */

// Load environment variables
require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');

const app = express();
const PORT = 8000;

// Initialize Stripe with mode toggle
const stripeMode = (process.env.STRIPE_MODE || 'test').toLowerCase();
const stripeKey = stripeMode === 'live'
  ? process.env.STRIPE_SECRET_KEY_LIVE
  : process.env.STRIPE_SECRET_KEY_TEST;
const webhookSecret = stripeMode === 'live'
  ? process.env.STRIPE_WEBHOOK_SECRET_LIVE
  : process.env.STRIPE_WEBHOOK_SECRET_TEST;

if (!stripeKey) {
  console.error(`❌ [Stripe] No secret key found for ${stripeMode} mode! Check STRIPE_SECRET_KEY_${stripeMode.toUpperCase()} in .env`);
  process.exit(1);
}

const stripe = require('stripe')(stripeKey);
console.log(`[Stripe] Initialized in ${stripeMode === 'live' ? '🔴 LIVE' : '🟡 TEST'} mode`);

// Initialize Supabase
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

// Middleware
app.use(cors({
  origin: ['http://localhost:3000', 'https://buckets.media'],
  credentials: true
}));

// Parse JSON for all routes except webhook (needs raw body)
app.use((req, res, next) => {
  if (req.path === '/stripe/webhook') {
    next();
  } else {
    express.json()(req, res, next);
  }
});

// =============================================================================
// HEALTH CHECK
// =============================================================================

app.get('/', (req, res) => {
  res.json({
    message: 'Bucket & MediaID API',
    version: '1.0.0',
    status: 'healthy'
  });
});

// =============================================================================
// STRIPE ROUTES
// =============================================================================

/**
 * POST /stripe/create-checkout-session
 * Create a Stripe Checkout session
 */
app.post('/stripe/create-checkout-session', async (req, res) => {
  try {
    const { 
      mode, 
      intent, 
      lineItems, 
      metadata, 
      successUrl, 
      cancelUrl, 
      customerId,
      // Single item format (from useStripeCheckout)
      productType,
      productId,
      eventId,
      tier,
      amountCents,
      userId,
      customerEmail
    } = req.body;

    console.log('[Stripe] Creating checkout session:', { intent, mode, productType, amountCents });

    if (!stripeKey) {
      return res.status(500).json({ error: `Stripe not configured for ${stripeMode} mode` });
    }

    // Construct line items - support both formats
    let items = [];
    if (lineItems && Array.isArray(lineItems)) {
      // Line items format
      items = lineItems.map(item => ({
        price_data: {
          currency: 'usd',
          product_data: {
            name: item.name || 'Event Ticket',
            description: item.description,
          },
          unit_amount: item.price || item.amountCents,
        },
        quantity: item.quantity || 1,
      }));
    } else if (amountCents) {
      // Single item format (from frontend hook)
      items = [{
        price_data: {
          currency: 'usd',
          product_data: {
            name: tier ? `${tier} Ticket` : 'Event Ticket',
            description: eventId ? `Event: ${eventId}` : undefined,
          },
          unit_amount: amountCents,
        },
        quantity: 1,
      }];
    } else {
      return res.status(400).json({ error: 'No line items or amount provided' });
    }

    // Create Stripe checkout session
    const appUrl = process.env.APP_URL || 'http://localhost:3000';
    const session = await stripe.checkout.sessions.create({
      mode: mode || 'payment',
      line_items: items,
      success_url: successUrl || `${appUrl}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: cancelUrl || `${appUrl}/checkout/cancel`,
      client_reference_id: userId,
      customer_email: customerEmail,
      metadata: {
        intent: intent || productType,
        productId,
        eventId,
        tier,
        userId,
        ...metadata
      },
      ...(customerId && { customer: customerId }),
    });

    console.log('[Stripe] Session created:', session.id);

    res.json({
      sessionId: session.id,
      url: session.url
    });

  } catch (error) {
    console.error('[Stripe] Create checkout error:', error.message);
    console.error('[Stripe] Stack:', error.stack);
    res.status(500).json({ error: error.message || 'Failed to create checkout session' });
  }
});

/**
 * POST /stripe/webhook
 * Handle Stripe webhook events
 */
app.post('/stripe/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  try {
    const signature = req.headers['stripe-signature'];

    if (!signature || !webhookSecret) {
      return res.status(400).json({ error: 'Missing signature or webhook secret' });
    }

    // Verify webhook signature
    let event;
    try {
      event = stripe.webhooks.constructEvent(req.body, signature, webhookSecret);
    } catch (err) {
      console.error('[Stripe] Webhook signature verification failed:', err.message);
      return res.status(400).json({ error: 'Invalid signature' });
    }

    console.log('[Stripe] Webhook received:', event.type, event.id);

    // Check if event was already processed (idempotency)
    const { data: existingEvent } = await supabase
      .from('stripe_webhook_log')
      .select('id')
      .eq('stripe_event_id', event.id)
      .single();

    if (existingEvent) {
      console.log(`[Stripe] Event ${event.id} already processed, skipping`);
      return res.json({ received: true, status: 'duplicate' });
    }

    // Log the event
    await supabase.from('stripe_webhook_log').insert({
      stripe_event_id: event.id,
      event_type: event.type,
      payload: event,
      processed_at: new Date().toISOString(),
    });

    // Handle different event types
    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutCompleted(event.data.object);
        break;

      case 'payment_intent.succeeded':
        console.log('[Stripe] Payment succeeded:', event.data.object.id);
        break;

      case 'customer.subscription.updated':
        console.log('[Stripe] Subscription updated:', event.data.object.id);
        break;

      case 'customer.subscription.deleted':
        console.log('[Stripe] Subscription deleted:', event.data.object.id);
        break;

      default:
        console.log(`[Stripe] Unhandled event type: ${event.type}`);
    }

    res.json({ received: true });

  } catch (error) {
    console.error('[Stripe] Webhook error:', error.message);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

/**
 * POST /stripe/create-payment-intent
 * Create a payment intent for custom amounts
 */
app.post('/stripe/create-payment-intent', async (req, res) => {
  try {
    const { amount, currency = 'usd', metadata } = req.body;

    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency,
      automatic_payment_methods: { enabled: true },
      metadata
    });

    res.json({ clientSecret: paymentIntent.client_secret });

  } catch (error) {
    console.error('[Stripe] Create payment intent error:', error.message);
    res.status(500).json({ error: 'Failed to create payment intent' });
  }
});

/**
 * POST /stripe/create-portal-session
 * Create a Customer Portal session
 */
app.post('/stripe/create-portal-session', async (req, res) => {
  try {
    const { customerId, returnUrl } = req.body;

    if (!customerId) {
      return res.status(400).json({ error: 'Customer ID required' });
    }

    const session = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: returnUrl || 'http://localhost:3000/dashboard',
    });

    res.json({ url: session.url });

  } catch (error) {
    console.error('[Stripe] Create portal session error:', error.message);
    res.status(500).json({ error: 'Failed to create portal session' });
  }
});

// =============================================================================
// PASSPORT ROUTES
// =============================================================================

/**
 * POST /api/passport/log
 * Log event to Passport (called from frontend usePassport hook)
 */
app.post('/api/passport/log', async (req, res) => {
  const startTime = Date.now();

  try {
    const payload = req.body;

    // Validate required fields
    if (!payload.type || !payload.userId || !payload.at) {
      return res.status(400).json({
        error: 'Missing required fields: type, userId, at'
      });
    }

    console.log(`📥 [Passport API] Received event: ${payload.type}`);

    // Extract event category from type (e.g., "player.track_played" → "player")
    const eventCategory = payload.type.split('.')[0];

    // Extract entity info from payload
    let entityType = null;
    let entityId = null;

    if (payload.eventId) {
      entityType = 'event';
      entityId = payload.eventId;
    } else if (payload.artistId) {
      entityType = 'artist';
      entityId = payload.artistId;
    } else if (payload.trackId) {
      entityType = 'track';
      entityId = payload.trackId;
    } else if (payload.targetId) {
      entityType = payload.targetType || 'unknown';
      entityId = payload.targetId;
    }

    // Insert to passport_entries with new schema
    const { data, error } = await supabase
      .from('passport_entries')
      .insert({
        user_id: payload.userId,
        session_id: payload.sessionId || null,
        device_id: null,
        event_type: payload.type,
        event_category: eventCategory,
        entity_type: entityType,
        entity_id: entityId,
        metadata: payload,
        processed_by_mediaid: false,
        processed_by_treasury: false,
        processed_by_coliseum: false,
        dna_influence: null
      })
      .select();

    if (error) {
      console.error('❌ [Passport API] Database error:', error);
      return res.status(500).json({
        error: 'Failed to log event',
        details: error.message
      });
    }

    const elapsed = Date.now() - startTime;
    console.log(`✅ [Passport API] Event logged in ${elapsed}ms`);

    // Fast response (< 50ms protocol requirement)
    return res.status(201).json({
      ok: true,
      id: data[0]?.id,
      latency: elapsed
    });

  } catch (error) {
    const elapsed = Date.now() - startTime;
    console.error('❌ [Passport API] Error:', error);
    return res.status(500).json({
      error: 'Internal server error',
      message: error.message,
      latency: elapsed
    });
  }
});

/**
 * GET /api/passport/stats
 * Get Passport statistics (debug endpoint)
 */
app.get('/api/passport/stats', async (req, res) => {
  try {
    // Count total entries
    const { count: totalCount } = await supabase
      .from('passport_entries')
      .select('*', { count: 'exact', head: true });

    // Count unprocessed
    const { count: unprocessedCount } = await supabase
      .from('passport_entries')
      .select('*', { count: 'exact', head: true })
      .eq('processed_by_coliseum', false);

    return res.json({
      total_entries: totalCount || 0,
      unprocessed_entries: unprocessedCount || 0,
      status: 'healthy'
    });

  } catch (error) {
    console.error('[Passport Stats] Error:', error);
    return res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

// =============================================================================
// BADGE MANAGEMENT ROUTES
// =============================================================================

/**
 * GET /api/badges/:userId
 * Get all badges for a user
 */
app.get('/api/badges/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const { data, error } = await supabase
      .from('user_badges')
      .select('*')
      .eq('user_id', userId)
      .order('is_primary', { ascending: false })
      .order('created_at', { ascending: true });

    if (error) {
      console.error('[Badges] Error fetching badges:', error);
      return res.status(500).json({ error: 'Failed to fetch badges' });
    }

    return res.json({ badges: data || [] });
  } catch (error) {
    console.error('[Badges] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * POST /api/badges/request
 * Request a new badge (auto-verify for fan/brand/developer, require approval for artist)
 */
app.post('/api/badges/request', async (req, res) => {
  try {
    const { userId, badgeType, reason, verificationData } = req.body;

    if (!userId || !badgeType) {
      return res.status(400).json({ error: 'userId and badgeType are required' });
    }

    const validBadges = ['fan', 'artist', 'brand', 'developer'];
    if (!validBadges.includes(badgeType)) {
      return res.status(400).json({ error: 'Invalid badge type' });
    }

    // Check if badge already exists
    const { data: existing } = await supabase
      .from('user_badges')
      .select('id, verification_status')
      .eq('user_id', userId)
      .eq('badge_type', badgeType)
      .single();

    if (existing) {
      if (existing.verification_status === 'verified') {
        return res.status(400).json({ error: 'You already have this badge' });
      }
      if (existing.verification_status === 'pending') {
        return res.status(400).json({ error: 'Badge request is already pending' });
      }
    }

    // Determine if auto-verify
    const autoVerifyBadges = ['fan', 'brand', 'developer'];
    const shouldAutoVerify = autoVerifyBadges.includes(badgeType);

    // Count current badges to determine if this is the first
    const { count: badgeCount } = await supabase
      .from('user_badges')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('is_active', true);

    const isPrimary = (badgeCount || 0) === 0;

    const { data, error } = await supabase
      .from('user_badges')
      .upsert({
        user_id: userId,
        badge_type: badgeType,
        is_active: shouldAutoVerify,
        is_primary: isPrimary,
        verification_status: shouldAutoVerify ? 'verified' : 'pending',
        badge_metadata: {
          request_reason: reason || '',
          verification_data: verificationData || {},
        },
        onboarding_completed: false,
      }, { onConflict: 'user_id,badge_type' })
      .select()
      .single();

    if (error) {
      console.error('[Badges] Error creating badge:', error);
      return res.status(500).json({ error: 'Failed to request badge' });
    }

    // Update profiles cache if auto-verified
    if (shouldAutoVerify) {
      const { data: profile } = await supabase
        .from('profiles')
        .select('all_badges')
        .eq('id', userId)
        .single();

      const currentBadges = profile?.all_badges || [];
      if (!currentBadges.includes(badgeType)) {
        await supabase
          .from('profiles')
          .update({ all_badges: [...currentBadges, badgeType] })
          .eq('id', userId);
      }
    }

    // Log to Passport
    await logPassportEvent({
      userId,
      eventType: 'badge.requested',
      eventCategory: 'system',
      payload: {
        badge_type: badgeType,
        auto_verified: shouldAutoVerify,
        reason,
      }
    });

    console.log(`[Badges] ✅ Badge ${badgeType} ${shouldAutoVerify ? 'granted' : 'requested'} for user ${userId}`);
    return res.status(201).json({ badge: data, autoVerified: shouldAutoVerify });

  } catch (error) {
    console.error('[Badges] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * PUT /api/badges/set-primary
 * Set a user's primary badge
 */
app.put('/api/badges/set-primary', async (req, res) => {
  try {
    const { userId, badgeType } = req.body;

    if (!userId || !badgeType) {
      return res.status(400).json({ error: 'userId and badgeType are required' });
    }

    // Verify badge exists and is verified
    const { data: badge } = await supabase
      .from('user_badges')
      .select('id')
      .eq('user_id', userId)
      .eq('badge_type', badgeType)
      .eq('is_active', true)
      .eq('verification_status', 'verified')
      .single();

    if (!badge) {
      return res.status(400).json({ error: 'User does not have a verified badge of this type' });
    }

    // Remove primary from all
    await supabase
      .from('user_badges')
      .update({ is_primary: false })
      .eq('user_id', userId);

    // Set new primary
    await supabase
      .from('user_badges')
      .update({ is_primary: true })
      .eq('user_id', userId)
      .eq('badge_type', badgeType);

    // Update profiles cache
    await supabase
      .from('profiles')
      .update({ primary_badge: badgeType, role: badgeType })
      .eq('id', userId);

    console.log(`[Badges] ✅ Primary badge set to ${badgeType} for user ${userId}`);
    return res.json({ success: true, primaryBadge: badgeType });

  } catch (error) {
    console.error('[Badges] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * GET /api/badges/pending
 * Admin: List all pending badge requests
 */
app.get('/api/badges/pending', async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('user_badges')
      .select(`
        *,
        profiles!user_badges_user_id_fkey (display_name, avatar_url)
      `)
      .eq('verification_status', 'pending')
      .order('created_at', { ascending: true });

    if (error) {
      console.error('[Badges] Error fetching pending:', error);
      return res.status(500).json({ error: 'Failed to fetch pending badges' });
    }

    return res.json({ pending: data || [] });
  } catch (error) {
    console.error('[Badges] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * PUT /api/badges/verify
 * Admin: Approve or reject a badge request
 */
app.put('/api/badges/verify', async (req, res) => {
  try {
    const { badgeId, action, verifiedBy } = req.body;

    if (!badgeId || !action || !verifiedBy) {
      return res.status(400).json({ error: 'badgeId, action, and verifiedBy are required' });
    }

    if (!['approve', 'reject'].includes(action)) {
      return res.status(400).json({ error: 'action must be "approve" or "reject"' });
    }

    const { data: badge, error: fetchError } = await supabase
      .from('user_badges')
      .select('*')
      .eq('id', badgeId)
      .single();

    if (fetchError || !badge) {
      return res.status(404).json({ error: 'Badge not found' });
    }

    const updates = {
      verification_status: action === 'approve' ? 'verified' : 'rejected',
      is_active: action === 'approve',
      verified_by: verifiedBy,
      verified_at: new Date().toISOString(),
    };

    const { error: updateError } = await supabase
      .from('user_badges')
      .update(updates)
      .eq('id', badgeId);

    if (updateError) {
      console.error('[Badges] Error verifying badge:', updateError);
      return res.status(500).json({ error: 'Failed to verify badge' });
    }

    // If approved, update profiles cache
    if (action === 'approve') {
      const { data: profile } = await supabase
        .from('profiles')
        .select('all_badges')
        .eq('id', badge.user_id)
        .single();

      const currentBadges = profile?.all_badges || [];
      if (!currentBadges.includes(badge.badge_type)) {
        await supabase
          .from('profiles')
          .update({ all_badges: [...currentBadges, badge.badge_type] })
          .eq('id', badge.user_id);
      }
    }

    // Log to Passport
    await logPassportEvent({
      userId: badge.user_id,
      eventType: `badge.${action === 'approve' ? 'approved' : 'rejected'}`,
      eventCategory: 'system',
      payload: {
        badge_type: badge.badge_type,
        badge_id: badgeId,
        verified_by: verifiedBy,
        action,
      }
    });

    console.log(`[Badges] ✅ Badge ${badgeId} ${action}d by ${verifiedBy}`);
    return res.json({ success: true, action, badge: { ...badge, ...updates } });

  } catch (error) {
    console.error('[Badges] Error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// =============================================================================
// TREASURY TEST ROUTES
// =============================================================================

const PLATFORM_RESERVE_ID = '00000000-0000-0000-0000-000000000000';

/**
 * POST /api/treasury/add-funds
 * Add funds to a user's account (test adjustment — single credit entry)
 * Note: Skips platform debit because PLATFORM_RESERVE_ID doesn't exist in users table.
 * For production, a platform system user must be created first.
 */
app.post('/api/treasury/add-funds', async (req, res) => {
  try {
    const { userId, amountCents, description } = req.body;

    if (!userId || !amountCents) {
      return res.status(400).json({ error: 'userId and amountCents are required' });
    }

    if (amountCents <= 0 || amountCents > 100000000) {
      return res.status(400).json({ error: 'amountCents must be between 1 and 1,000,000.00' });
    }

    const correlationId = `add-funds-${Date.now()}-${Math.random().toString(36).substr(2, 6)}`;
    const referenceId = `test_add_funds_${Date.now()}`;
    const desc = description || `Test funds added: $${(amountCents / 100).toFixed(2)}`;

    // 1. Credit user account (test adjustment — no platform debit needed)
    const { error: creditError } = await supabase
      .from('ledger_entries')
      .insert({
        user_id: userId,
        amount_cents: amountCents,
        currency: 'USD',
        type: 'credit',
        event_source: 'adjustment',
        reference_id: referenceId,
        correlation_id: correlationId,
        description: desc,
        metadata: { test: true, source: 'test_treasury_page', adjustment_type: 'test_funding' }
      });

    if (creditError) {
      console.error('[Treasury] Credit error:', creditError);
      return res.status(500).json({ error: 'Failed to create credit entry', details: creditError.message });
    }

    // 2. Get new balance
    const { data: balanceData } = await supabase
      .from('ledger_entries')
      .select('amount_cents, type')
      .eq('user_id', userId);

    let newBalance = 0;
    if (balanceData) {
      for (const entry of balanceData) {
        if (entry.type === 'credit') newBalance += entry.amount_cents;
        else if (entry.type === 'debit') newBalance -= entry.amount_cents;
      }
    }

    // 3. Log to Passport (using correct column names: metadata, not event_data)
    try {
      await supabase
        .from('passport_entries')
        .insert({
          user_id: userId,
          event_type: 'treasury.funds_added',
          event_category: 'interaction',
          metadata: {
            amount_cents: amountCents,
            correlation_id: correlationId,
            new_balance_cents: newBalance,
            source: 'test_treasury_page'
          }
        });
      console.log(`[Passport] ✅ Logged treasury.funds_added for ${userId}`);
    } catch (passportErr) {
      console.error('[Passport] Failed to log funds_added:', passportErr);
    }

    console.log(`[Treasury] ✅ Added $${(amountCents / 100).toFixed(2)} to user ${userId} | Balance: $${(newBalance / 100).toFixed(2)}`);

    return res.json({
      success: true,
      correlationId,
      newBalance,
      amountAdded: amountCents,
      description: desc
    });

  } catch (error) {
    console.error('[Treasury] Add funds error:', error);
    return res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});


/**
 * POST /api/treasury/connect-event
 * Load event details and split rules for testing
 */
app.post('/api/treasury/connect-event', async (req, res) => {
  try {
    const { eventId, splitOverrides } = req.body;

    if (!eventId) {
      return res.status(400).json({ error: 'eventId is required' });
    }

    // 1. Get event details
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select('*')
      .eq('id', eventId)
      .single();

    if (eventError || !event) {
      return res.status(404).json({ error: 'Event not found', details: eventError?.message });
    }

    // 2. Get confirmed artists
    const { data: eventArtists } = await supabase
      .from('event_artist_prospects')
      .select('*, profiles!event_artist_prospects_migrated_to_user_id_fkey(display_name, avatar_url)')
      .eq('event_id', eventId)
      .not('migrated_to_user_id', 'is', null);

    // 3. Get host profile
    let hostProfile = null;
    if (event.host_user_id) {
      const { data: hp } = await supabase
        .from('profiles')
        .select('id, display_name, avatar_url, primary_badge')
        .eq('id', event.host_user_id)
        .single();
      hostProfile = hp;
    }

    // 4. Get existing split rules
    const { data: splitRule } = await supabase
      .from('split_rules')
      .select('*')
      .eq('entity_type', 'event')
      .eq('entity_id', eventId)
      .eq('is_active', true)
      .maybeSingle();

    let activeSplitRules = splitRule?.rules || null;

    // 5. If no specific rules, get default
    if (!activeSplitRules) {
      const { data: defaultRule } = await supabase
        .from('split_rules')
        .select('*')
        .eq('is_default', true)
        .eq('is_active', true)
        .maybeSingle();

      activeSplitRules = defaultRule?.rules || [
        { role: 'artist', percent: 70 },
        { role: 'platform', percent: 20 },
        { role: 'host', percent: 10 }
      ];
    }

    // 6. If splitOverrides provided, create/update event-specific split rule
    if (splitOverrides && Array.isArray(splitOverrides)) {
      const totalPercent = splitOverrides.reduce((sum, s) => sum + s.percent, 0);
      if (totalPercent !== 100) {
        return res.status(400).json({ error: `Split percentages must total 100%, got ${totalPercent}%` });
      }

      const { error: upsertError } = await supabase
        .from('split_rules')
        .upsert({
          entity_type: 'event',
          entity_id: eventId,
          owner_id: event.host_user_id || PLATFORM_RESERVE_ID,
          name: `Custom splits for ${event.title || eventId}`,
          rules: splitOverrides,
          is_default: false,
          is_active: true
        }, { onConflict: 'entity_type,entity_id' });

      if (upsertError) {
        console.error('[Treasury] Split rule upsert error:', upsertError);
      } else {
        activeSplitRules = splitOverrides;
        console.log('[Treasury] Updated split rules for event:', eventId);
      }
    }

    // 7. Get profit share partners
    const { data: partners } = await supabase
      .from('event_profit_share_partners')
      .select('*')
      .eq('event_id', eventId)
      .eq('is_active', true);

    console.log(`[Treasury] Event loaded: ${event.title} with ${eventArtists?.length || 0} artists`);

    return res.json({
      event: {
        id: event.id,
        title: event.title,
        code: event.code,
        start_date: event.start_date,
        location: event.location,
        host_user_id: event.host_user_id,
        status: event.status
      },
      host: hostProfile,
      artists: (eventArtists || []).map(a => ({
        id: a.id,
        userId: a.migrated_to_user_id,
        name: a.profiles?.display_name || a.artist_name || 'Unknown',
        avatar: a.profiles?.avatar_url
      })),
      splitRules: activeSplitRules,
      partners: partners || [],
      hasCustomRules: !!splitRule
    });

  } catch (error) {
    console.error('[Treasury] Connect event error:', error);
    return res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

/**
 * POST /api/treasury/connect-artist
 * Connect an existing user (with artist badge) to an event as a confirmed artist.
 * This creates an event_artist_prospects row linking the artist to the event,
 * enabling revenue split distribution.
 */
app.post('/api/treasury/connect-artist', async (req, res) => {
  try {
    const { eventId, artistUserId, artistName } = req.body;

    if (!eventId || !artistUserId) {
      return res.status(400).json({ error: 'eventId and artistUserId are required' });
    }

    // 1. Verify event exists
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select('id, title, host_user_id')
      .eq('id', eventId)
      .single();

    if (eventError || !event) {
      return res.status(404).json({ error: 'Event not found' });
    }

    // 2. Verify user exists and has artist badge
    const { data: profile } = await supabase
      .from('profiles')
      .select('id, display_name')
      .eq('id', artistUserId)
      .single();

    const { data: artistBadge } = await supabase
      .from('user_badges')
      .select('id, badge_type, is_active')
      .eq('user_id', artistUserId)
      .eq('badge_type', 'artist')
      .eq('is_active', true)
      .maybeSingle();

    const displayName = artistName || profile?.display_name || 'Unknown Artist';

    // 3. Check if artist is already connected to this event
    const { data: existing } = await supabase
      .from('event_artist_prospects')
      .select('id')
      .eq('event_id', eventId)
      .eq('migrated_to_user_id', artistUserId)
      .maybeSingle();

    if (existing) {
      return res.json({
        success: true,
        message: 'Artist already connected to this event',
        artistProspectId: existing.id,
        alreadyConnected: true
      });
    }

    // 4. Create event_artist_prospects row
    const registrationToken = `reg_${Date.now()}_${Math.random().toString(36).substr(2, 8)}`;
    const { data: prospect, error: insertError } = await supabase
      .from('event_artist_prospects')
      .insert({
        event_id: eventId,
        artist_name: displayName,
        contact_status: 'confirmed',
        migrated_to_user_id: artistUserId,
        registration_token: registrationToken,
        email: null,
        instagram_handle: null,
        profile_image_url: profile?.avatar_url || null,
        bio: null,
        tags: artistBadge ? ['verified_artist'] : ['unverified']
      })
      .select()
      .single();

    if (insertError) {
      console.error('[Treasury] Connect artist error:', insertError);
      return res.status(500).json({ error: 'Failed to connect artist', details: insertError.message });
    }

    // 5. Log to Passport
    await supabase
      .from('passport_entries')
      .insert({
        user_id: artistUserId,
        event_type: 'treasury.artist_connected',
        event_category: 'financial',
        metadata: {
          event_id: eventId,
          event_title: event.title,
          prospect_id: prospect.id,
          has_artist_badge: !!artistBadge,
          source: 'test_treasury_page'
        }
      });

    console.log(`[Treasury] ✅ Connected artist "${displayName}" to event "${event.title}"`);

    return res.json({
      success: true,
      artistProspectId: prospect.id,
      artistName: displayName,
      eventTitle: event.title,
      hasArtistBadge: !!artistBadge,
      alreadyConnected: false
    });

  } catch (error) {
    console.error('[Treasury] Connect artist error:', error);
    return res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

/**
 * POST /api/treasury/apply-splits
 * Apply revenue splits for a test event purchase
 */
app.post('/api/treasury/apply-splits', async (req, res) => {
  try {
    const { eventId, amountCents, buyerUserId } = req.body;

    if (!eventId || !amountCents || !buyerUserId) {
      return res.status(400).json({ error: 'eventId, amountCents, and buyerUserId are required' });
    }

    // 1. Create a mock purchase record
    const { data: purchase, error: purchaseError } = await supabase
      .from('purchases')
      .insert({
        user_id: buyerUserId,
        product_type: 'ticket',
        product_id: eventId,
        amount_cents: amountCents,
        currency: 'USD',
        status: 'completed',
        fulfillment_status: 'pending',
        metadata: {
          test: true,
          source: 'test_treasury_page',
          eventId
        },
        completed_at: new Date().toISOString()
      })
      .select()
      .single();

    if (purchaseError) {
      console.error('[Treasury] Mock purchase error:', purchaseError);
      return res.status(500).json({ error: 'Failed to create mock purchase', details: purchaseError.message });
    }

    // 2. Build mock session for applyRevenueSplits
    const mockSession = {
      id: `test_session_${Date.now()}`,
      amount_total: amountCents,
      currency: 'usd',
      metadata: { eventId, intent: 'ticket' }
    };

    // 3. Apply splits (reuse existing function)
    await applyRevenueSplits(purchase, mockSession);

    // 4. Fetch the created splits from ledger
    const { data: splitEntries } = await supabase
      .from('ledger_entries')
      .select('*')
      .eq('reference_id', purchase.id)
      .eq('event_source', 'split')
      .order('created_at', { ascending: true });

    // 5. Log to Passport
    await logPassportEvent({
      userId: buyerUserId,
      eventType: 'treasury.test_splits_applied',
      eventCategory: 'interaction',
      payload: {
        purchase_id: purchase.id,
        event_id: eventId,
        amount_cents: amountCents,
        splits_created: splitEntries?.length || 0,
        source: 'test_treasury_page'
      }
    });

    console.log(`[Treasury] ✅ Test splits applied: ${splitEntries?.length || 0} entries for $${(amountCents / 100).toFixed(2)}`);

    return res.json({
      success: true,
      purchaseId: purchase.id,
      splits: (splitEntries || []).map(e => ({
        userId: e.user_id,
        role: e.metadata?.role || 'unknown',
        amountCents: e.amount_cents,
        percent: e.metadata?.split_percent,
        description: e.description,
        correlationId: e.correlation_id
      })),
      totalAmount: amountCents,
      splitsCreated: splitEntries?.length || 0
    });

  } catch (error) {
    console.error('[Treasury] Apply splits error:', error);
    return res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

/**
 * GET /api/treasury/user-status/:userId
 * Get user role, badge status, hosted events, and wallet balance
 */
app.get('/api/treasury/user-status/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    // 1. Get user profile
    const { data: profile } = await supabase
      .from('profiles')
      .select('id, display_name, avatar_url, primary_badge, all_badges, role')
      .eq('id', userId)
      .single();

    // 2. Get user badges
    const { data: badges } = await supabase
      .from('user_badges')
      .select('*')
      .eq('user_id', userId)
      .order('is_primary', { ascending: false });

    // 3. Check host status (events they host)
    const { data: hostedEvents } = await supabase
      .from('events')
      .select('id, title, code, start_date, status')
      .eq('host_user_id', userId)
      .order('start_date', { ascending: false })
      .limit(10);

    // 4. Check artist status (events they perform at)
    const { data: artistEvents } = await supabase
      .from('event_artist_prospects')
      .select('id, event_id, artist_name, status, events(title, start_date)')
      .eq('migrated_to_user_id', userId)
      .order('created_at', { ascending: false })
      .limit(10);

    // 5. Get wallet balance from ledger
    const { data: ledgerData } = await supabase
      .from('ledger_entries')
      .select('amount_cents, type')
      .eq('user_id', userId);

    let balance = 0;
    if (ledgerData) {
      for (const entry of ledgerData) {
        if (entry.type === 'credit') balance += entry.amount_cents;
        else if (entry.type === 'debit') balance -= entry.amount_cents;
      }
    }

    // 6. Get recent passport activity count
    const { count: passportCount } = await supabase
      .from('passport_entries')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);

    const isHost = (hostedEvents && hostedEvents.length > 0);
    const isArtist = badges?.some(b => b.badge_type === 'artist' && b.is_active) || false;

    console.log(`[Treasury] User status loaded for ${profile?.display_name || userId}`);

    return res.json({
      profile: profile || { id: userId },
      badges: badges || [],
      primaryBadge: profile?.primary_badge || null,
      isHost,
      isArtist,
      hostedEvents: hostedEvents || [],
      artistEvents: artistEvents || [],
      balance,
      balanceFormatted: `$${(balance / 100).toFixed(2)}`,
      passportEntryCount: passportCount || 0
    });

  } catch (error) {
    console.error('[Treasury] User status error:', error);
    return res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

/**
 * GET /api/treasury/logs/:userId
 * Get passport entries and ledger entries for a user
 */
app.get('/api/treasury/logs/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const limit = parseInt(req.query.limit) || 50;

    // 1. Get recent passport entries
    const { data: passportEntries, error: passportError } = await supabase
      .from('passport_entries')
      .select('id, event_type, event_category, entity_type, entity_id, metadata, created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (passportError) {
      console.error('[Treasury] Passport entries error:', passportError);
    }

    // 2. Get recent ledger entries
    const { data: ledgerEntries, error: ledgerError } = await supabase
      .from('ledger_entries')
      .select('id, amount_cents, currency, type, event_source, reference_id, correlation_id, description, metadata, created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (ledgerError) {
      console.error('[Treasury] Ledger entries error:', ledgerError);
    }

    // 3. Calculate summary
    let totalCredits = 0;
    let totalDebits = 0;
    if (ledgerEntries) {
      for (const e of ledgerEntries) {
        if (e.type === 'credit') totalCredits += e.amount_cents;
        else if (e.type === 'debit') totalDebits += e.amount_cents;
      }
    }

    // 4. Group passport entries by category
    const categoryCounts = {};
    if (passportEntries) {
      for (const e of passportEntries) {
        const cat = e.event_category || 'unknown';
        categoryCounts[cat] = (categoryCounts[cat] || 0) + 1;
      }
    }

    return res.json({
      passportEntries: passportEntries || [],
      ledgerEntries: ledgerEntries || [],
      summary: {
        passportCount: passportEntries?.length || 0,
        ledgerCount: ledgerEntries?.length || 0,
        totalCredits,
        totalDebits,
        netBalance: totalCredits - totalDebits,
        categoryCounts
      }
    });

  } catch (error) {
    console.error('[Treasury] Logs error:', error);
    return res.status(500).json({ error: 'Internal server error', message: error.message });
  }
});

// =============================================================================
// WEBHOOK HELPERS
// =============================================================================

async function handleCheckoutCompleted(session) {
  console.log('[Treasury] Processing checkout.session.completed:', session.id);

  const intent = session.metadata?.intent || session.metadata?.productType;
  const userId = session.client_reference_id || session.metadata?.userId;

  if (!userId) {
    console.error('[Treasury] No user ID found in checkout session');
    return;
  }

  try {
    // 1. Log to Passport: purchase.initiated
    await logPassportEvent({
      userId,
      eventType: 'purchase.completed',
      eventCategory: 'interaction',
      payload: {
        checkout_session_id: session.id,
        payment_intent_id: session.payment_intent,
        amount_cents: session.amount_total,
        currency: session.currency,
        intent,
        metadata: session.metadata
      }
    });

    // 2. Create purchase record
    const { data: purchase, error: purchaseError } = await supabase
      .from('purchases')
      .insert({
        user_id: userId,
        product_type: intent || 'ticket',
        product_id: session.metadata?.eventId || session.metadata?.productId,
        stripe_checkout_session_id: session.id,
        stripe_payment_intent_id: session.payment_intent,
        amount_cents: session.amount_total,
        currency: session.currency,
        status: 'completed',
        fulfillment_status: 'pending',
        metadata: session.metadata,
        completed_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (purchaseError) {
      console.error('[Treasury] Error creating purchase record:', purchaseError);
      return;
    }

    console.log('[Treasury] Purchase record created:', purchase.id);

    // 3. Fulfill based on intent
    switch (intent) {
      case 'ticket':
      case 'purchase':
        await fulfillTicket(purchase, session, userId);
        break;
      case 'drop':
        await fulfillDrop(purchase, session, userId);
        break;
      case 'membership':
        await fulfillMembership(purchase, session, userId);
        break;
      default:
        console.log(`[Treasury] Unknown intent: ${intent}`);
    }

    // 4. Log treasury.money_spent to Passport (for Coliseum G-domain analytics)
    // Get event artists for attribution
    const eventId = session.metadata?.eventId;
    if (eventId) {
      const { data: eventArtists } = await supabase
        .from('event_artist_prospects')
        .select('migrated_to_user_id')
        .eq('event_id', eventId)
        .not('migrated_to_user_id', 'is', null);

      const confirmedArtists = eventArtists || [];
      
      // Log one treasury.money_spent event per artist (Coliseum requirement)
      // Gross amount before splits - Coliseum will calculate net from splits
      for (const artist of confirmedArtists) {
        if (artist.migrated_to_user_id) {
          await logPassportEvent({
            userId: userId,
            eventType: 'treasury.money_spent',
            eventCategory: 'interaction',
            payload: {
              artistId: artist.migrated_to_user_id,  // Required for Coliseum
              amountCents: session.amount_total,     // Gross amount (before splits)
              reason: 'ticket',                       // Required: ticket | tip | subscription
              eventId: eventId,                       // Required if event-related
              purchaseId: purchase.id,
              checkoutSessionId: session.id
            }
          });
        }
      }
      
      // If no artists confirmed, log with eventId only (Coliseum can aggregate later)
      if (confirmedArtists.length === 0) {
        await logPassportEvent({
          userId: userId,
          eventType: 'treasury.money_spent',
          eventCategory: 'interaction',
          payload: {
            amountCents: session.amount_total,
            reason: 'ticket',
            eventId: eventId,
            purchaseId: purchase.id,
            checkoutSessionId: session.id,
            note: 'No confirmed artists at time of purchase'
          }
        });
      }
    }

    // 5. Apply revenue splits (Treasury integration)
    await applyRevenueSplits(purchase, session);

    // 6. Update purchase fulfillment status
    await supabase
      .from('purchases')
      .update({ fulfillment_status: 'fulfilled' })
      .eq('id', purchase.id);

    console.log('[Treasury] ✅ Purchase fulfilled:', purchase.id);
    
  } catch (error) {
    console.error('[Treasury] Error in handleCheckoutCompleted:', error);
  }
}

/**
 * Log event to Passport
 */
async function logPassportEvent({ userId, eventType, eventCategory, payload }) {
  try {
    const { error } = await supabase
      .from('passport_entries')
      .insert({
        user_id: userId,
        event_type: eventType,
        event_category: eventCategory,
        metadata: payload
      });

    if (error) {
      console.error('[Passport] Error logging event:', error);
    } else {
      console.log(`[Passport] ✅ Logged ${eventType} for user ${userId}`);
    }
  } catch (err) {
    console.error('[Passport] Failed to log event:', err);
  }
}


/**
 * Fulfill ticket purchase
 */
async function fulfillTicket(purchase, session, userId) {
  console.log('[Treasury] Fulfilling ticket for purchase:', purchase.id);

  try {
    const eventId = session.metadata?.eventId;
    const tier = session.metadata?.tier || 'general';
    const tierDisplayName = session.metadata?.tier ? 
      session.metadata.tier.charAt(0).toUpperCase() + session.metadata.tier.slice(1) + ' Admission' :
      'General Admission';

    // Get event details
    const { data: event } = await supabase
      .from('events')
      .select('title, start_date, location, video_thumbnail_url')
      .eq('id', eventId)
      .single();

    // Generate ticket number
    const ticketNumber = await generateTicketNumber();
    
    // Generate QR code data (signed JWT would be better in production)
    const qrCodeData = `BKT-${purchase.id}-${Date.now()}`;
    
    // Generate validation secret
    const validationSecret = require('crypto').randomBytes(32).toString('hex');

    // Create ticket
    const { data: ticket, error: ticketError } = await supabase
      .from('event_tickets')
      .insert({
        user_id: userId,
        attendee_id: userId,
        purchase_id: purchase.id,
        event_id: eventId,
        event_title: event?.title || 'Event',
        event_date: event?.start_date,
        event_venue: event?.location,
        event_image_url: event?.video_thumbnail_url,
        ticket_tier: tier,
        tier: tier.toLowerCase(),
        tier_display_name: tierDisplayName,
        ticket_code: ticketNumber,
        ticket_number: ticketNumber,
        qr_code_data: qrCodeData,
        validation_secret: validationSecret,
        price_cents: purchase.amount_cents,
        status: 'active',
        is_redeemed: false,
        perks: session.metadata?.perks ? JSON.parse(session.metadata.perks) : [],
        metadata: {
          purchase_id: purchase.id,
          checkout_session_id: session.id
        },
        issued_at: new Date().toISOString(),
        valid_from: new Date().toISOString(),
        valid_until: event?.start_date ? new Date(new Date(event.start_date).getTime() + 24*60*60*1000).toISOString() : null
      })
      .select()
      .single();

    if (ticketError) {
      console.error('[Treasury] Error creating ticket:', ticketError);
      throw ticketError;
    }

    console.log('[Treasury] ✅ Ticket created:', ticket.id, ticketNumber);

    // Log to Passport
    await logPassportEvent({
      userId,
      eventType: 'ticket.issued',
      eventCategory: 'interaction',
      payload: {
        ticket_id: ticket.id,
        ticket_number: ticketNumber,
        event_id: eventId,
        purchase_id: purchase.id,
        tier: tier
      }
    });

    return ticket;
  } catch (error) {
    console.error('[Treasury] Error in fulfillTicket:', error);
    throw error;
  }
}

/**
 * Generate unique ticket number
 */
async function generateTicketNumber() {
  const year = new Date().getFullYear();
  const random = Math.floor(Math.random() * 999999).toString().padStart(6, '0');
  return `BKT-${year}-${random}`;
}

/**
 * Apply revenue splits with custom rules, partners, and venue
 */
async function applyRevenueSplits(purchase, session) {
  console.log('[Treasury] Applying revenue splits for purchase:', purchase.id);
  
  try {
    const eventId = session.metadata?.eventId;
    if (!eventId) {
      console.log('[Treasury] No eventId in session metadata, skipping splits');
      return;
    }

    const totalAmount = purchase.amount_cents;
    const correlationId = `split-${purchase.id}-${Date.now()}`;
    const splits = [];

    // 1. Get event-specific split rules (or default if none)
    let splitRules = [];
    const { data: eventSplitRule } = await supabase
      .from('split_rules')
      .select('*')
      .eq('entity_type', 'event')
      .eq('entity_id', eventId)
      .eq('is_active', true)
      .maybeSingle();

    if (eventSplitRule && eventSplitRule.rules) {
      splitRules = eventSplitRule.rules;
      console.log('[Treasury] Using event-specific split rules:', splitRules);
    } else {
      // Fallback to default split rule
      const { data: defaultRule } = await supabase
        .from('split_rules')
        .select('*')
        .eq('is_default', true)
        .eq('is_active', true)
        .maybeSingle();

      if (defaultRule && defaultRule.rules) {
        splitRules = defaultRule.rules;
        console.log('[Treasury] Using default split rules:', splitRules);
      } else {
        // Hardcoded fallback (70/20/10)
        splitRules = [
          { role: 'artist', percent: 70 },
          { role: 'platform', percent: 20 },
          { role: 'host', percent: 10 }
        ];
        console.log('[Treasury] Using hardcoded fallback splits');
      }
    }

    // 2. Get event details for host
    const { data: event } = await supabase
      .from('events')
      .select('host_user_id')
      .eq('id', eventId)
      .single();

    // 3. Get confirmed artists for artist split distribution
    const { data: eventArtists } = await supabase
      .from('event_artist_prospects')
      .select('migrated_to_user_id')
      .eq('event_id', eventId)
      .not('migrated_to_user_id', 'is', null);

    const confirmedArtists = eventArtists || [];
    console.log(`[Treasury] Found ${confirmedArtists.length} confirmed artists`);

    // 4. Get profit share partners
    const { data: partners } = await supabase
      .from('event_profit_share_partners')
      .select('*')
      .eq('event_id', eventId)
      .eq('is_active', true);

    console.log(`[Treasury] Found ${partners?.length || 0} profit share partners`);

    // 5. Calculate splits from rules
    for (const rule of splitRules) {
      const amountCents = Math.floor(totalAmount * rule.percent / 100);

      if (rule.role === 'artist') {
        // Distribute artist split among confirmed artists
        if (confirmedArtists.length > 0) {
          const perArtistAmount = Math.floor(amountCents / confirmedArtists.length);
          for (const artist of confirmedArtists) {
            if (artist.migrated_to_user_id) {
              splits.push({
                user_id: artist.migrated_to_user_id,
                role: 'artist',
                amount_cents: perArtistAmount,
                percent: rule.percent / confirmedArtists.length,
                description: `Artist split (${(rule.percent / confirmedArtists.length).toFixed(2)}%) from ticket purchase`
              });
            }
          }
        } else {
          // No artists confirmed yet, hold in escrow or skip
          console.log('[Treasury] No confirmed artists, skipping artist split');
        }
      } else if (rule.role === 'host' && event?.host_user_id) {
        splits.push({
          user_id: event.host_user_id,
          role: 'host',
          amount_cents: amountCents,
          percent: rule.percent,
          description: `Host split (${rule.percent}%) from ticket purchase`
        });
      } else if (rule.role === 'venue') {
        // Venue split - need to identify venue user_id
        // For now, we'll need to add venue_user_id to events table or use a partner
        console.log('[Treasury] Venue split configured but venue user_id not yet implemented');
      } else if (rule.role === 'platform') {
        // Platform keeps its share (no ledger entry needed, already credited)
        console.log(`[Treasury] Platform split: ${amountCents} cents (${rule.percent}%)`);
      }
    }

    // 6. Add profit share partner splits
    if (partners && partners.length > 0) {
      for (const partner of partners) {
        const partnerAmount = Math.floor(totalAmount * parseFloat(partner.split_percent) / 100);
        const recipientUserId = partner.recipient_user_id;
        
        if (recipientUserId) {
          splits.push({
            user_id: recipientUserId,
            role: 'partner',
            amount_cents: partnerAmount,
            percent: parseFloat(partner.split_percent),
            description: `Profit share partner: ${partner.partner_name} (${partner.split_percent}%)`,
            metadata: {
              partner_id: partner.id,
              partner_key: partner.partner_key,
              partner_name: partner.partner_name
            }
          });
        } else {
          console.log(`[Treasury] Partner ${partner.partner_name} has no user_id, skipping`);
        }
      }
    }

    // 7. Create ledger entries for each split
    console.log(`[Treasury] Creating ${splits.length} ledger entries`);
    for (const split of splits) {
      // Credit entry for recipient
      const { error: creditError } = await supabase
        .from('ledger_entries')
        .insert({
          user_id: split.user_id,
          amount_cents: split.amount_cents,
          currency: purchase.currency || 'USD',
          type: 'credit',
          event_source: 'split',
          reference_id: purchase.id,
          correlation_id: correlationId,
          description: split.description,
          metadata: {
            purchase_id: purchase.id,
            event_id: eventId,
            role: split.role,
            split_percent: split.percent,
            ...split.metadata
          }
        });

      if (creditError) {
        console.error(`[Treasury] Error creating credit entry for ${split.role}:`, creditError);
      } else {
        console.log(`[Treasury] ✅ Created credit entry: ${split.role} - $${(split.amount_cents / 100).toFixed(2)}`);
      }
    }

    // 8. Log to Passport: revenue.split_applied (for Treasury tracking)
    await logPassportEvent({
      userId: purchase.user_id,
      eventType: 'revenue.split_applied',
      eventCategory: 'interaction',
      payload: {
        purchase_id: purchase.id,
        event_id: eventId,
        total_amount_cents: totalAmount,
        split_count: splits.length,
        splits: splits.map(s => ({
          role: s.role,
          amount_cents: s.amount_cents,
          percent: s.percent,
          user_id: s.user_id,
          artist_net_cents: s.role === 'artist' ? s.amount_cents : null  // Net revenue for Coliseum
        })),
        correlation_id: correlationId
      }
    });

    // 9. Log treasury.money_spent with net revenue per artist (for Coliseum G-domain)
    // This provides net revenue after splits for accurate analytics
    const artistSplits = splits.filter(s => s.role === 'artist');
    for (const artistSplit of artistSplits) {
      await logPassportEvent({
        userId: purchase.user_id,
        eventType: 'treasury.revenue_split_applied',
        eventCategory: 'interaction',
        payload: {
          artistId: artistSplit.user_id,           // Required for Coliseum
          amountCents: artistSplit.amount_cents,   // Net amount (after splits)
          grossAmountCents: totalAmount,           // Gross amount (before splits)
          reason: 'ticket',
          eventId: eventId,
          purchaseId: purchase.id,
          splitPercent: artistSplit.percent,
          correlationId: correlationId
        }
      });
    }

    console.log('[Treasury] ✅ Revenue splits applied successfully');
  } catch (error) {
    console.error('[Treasury] Error applying splits:', error);
    throw error;
  }
}

/**
 * Fulfill drop purchase (future)
 */
async function fulfillDrop(purchase, session, userId) {
  console.log('[Treasury] Fulfilling drop for purchase:', purchase.id);
  // TODO: Unlock locker content
  await logPassportEvent({
    userId,
    eventType: 'drop.unlocked',
    eventCategory: 'content',
    payload: { purchase_id: purchase.id }
  });
}

/**
 * Fulfill membership (future)
 */
async function fulfillMembership(purchase, session, userId) {
  console.log('[Treasury] Fulfilling membership for purchase:', purchase.id);
  // TODO: Update fan_memberships table
  await logPassportEvent({
    userId,
    eventType: 'membership.activated',
    eventCategory: 'subscription',
    payload: { purchase_id: purchase.id }
  });
}

// =============================================================================
// START SERVER
// =============================================================================

app.listen(PORT, () => {
  console.log(`\n🚀 Buckets Backend Server`);
  console.log(`📡 Running on http://localhost:${PORT}`);
  console.log(`🔐 Stripe: ${stripeKey ? '✅ Configured' : '❌ Not configured'}`);
  console.log(`💾 Supabase: ${process.env.SUPABASE_URL ? '✅ Connected' : '❌ Not configured'}`);
  console.log(`\n📋 Endpoints:`);
  console.log(`   GET  /`);
  console.log(`   POST /stripe/create-checkout-session`);
  console.log(`   POST /stripe/webhook`);
  console.log(`   POST /stripe/create-payment-intent`);
  console.log(`   POST /stripe/create-portal-session\n`);
});

