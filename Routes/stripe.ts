import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

interface StripeRoutes {
  createCheckoutSession: (req: Request) => Promise<Response>
  handleWebhook: (req: Request) => Promise<Response>
  createPaymentIntent: (req: Request) => Promise<Response>
  createPortalSession: (req: Request) => Promise<Response>
}

export const stripeRoutes: StripeRoutes = {
  /**
   * POST /stripe/create-checkout-session
   * Create a Stripe Checkout session for tickets, drops, memberships, etc.
   */
  async createCheckoutSession(req: Request): Promise<Response> {
    try {
      const { mode, intent, lineItems, metadata, successUrl, cancelUrl, customerId } = await req.json()

      if (!STRIPE_SECRET_KEY) {
        return new Response(
          JSON.stringify({ error: 'Stripe not configured' }),
          { status: 500, headers: { 'Content-Type': 'application/json' } }
        )
      }

      // Create Stripe checkout session
      const response = await fetch('https://api.stripe.com/v1/checkout/sessions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          mode,
          'line_items[0][price]': lineItems[0].price,
          'line_items[0][quantity]': lineItems[0].quantity.toString(),
          success_url: successUrl || 'http://localhost:3000/checkout/success?session_id={CHECKOUT_SESSION_ID}',
          cancel_url: cancelUrl || 'http://localhost:3000/checkout/cancel',
          'metadata[intent]': intent,
          ...(metadata && Object.entries(metadata).reduce((acc, [key, value]) => {
            acc[`metadata[${key}]`] = value as string
            return acc
          }, {} as Record<string, string>)),
          ...(customerId && { customer: customerId }),
        }).toString(),
      })

      if (!response.ok) {
        const error = await response.text()
        console.error('Stripe API error:', error)
        return new Response(
          JSON.stringify({ error: 'Failed to create checkout session' }),
          { status: response.status, headers: { 'Content-Type': 'application/json' } }
        )
      }

      const session = await response.json()

      return new Response(
        JSON.stringify({ sessionId: session.id, url: session.url }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    } catch (error) {
      console.error('Create checkout session error:', error)
      return new Response(
        JSON.stringify({ error: 'Internal server error' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }
  },

  /**
   * POST /stripe/webhook
   * Handle Stripe webhook events
   */
  async handleWebhook(req: Request): Promise<Response> {
    try {
      const signature = req.headers.get('stripe-signature')
      const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')

      if (!signature || !webhookSecret) {
        return new Response(
          JSON.stringify({ error: 'Missing signature or webhook secret' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        )
      }

      const body = await req.text()

      // In production, verify the signature properly using Stripe SDK
      // For now, parse the event
      let event
      try {
        const payload = JSON.parse(body)
        event = payload
      } catch (err) {
        console.error('Webhook parsing error:', err)
        return new Response(
          JSON.stringify({ error: 'Invalid payload' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        )
      }

      // Check if event was already processed (idempotency)
      const { data: existingEvent } = await supabase
        .from('stripe_webhook_log')
        .select('id')
        .eq('stripe_event_id', event.id)
        .single()

      if (existingEvent) {
        console.log(`Event ${event.id} already processed, skipping`)
        return new Response(
          JSON.stringify({ received: true, status: 'duplicate' }),
          { status: 200, headers: { 'Content-Type': 'application/json' } }
        )
      }

      // Log the event
      await supabase.from('stripe_webhook_log').insert({
        stripe_event_id: event.id,
        event_type: event.type,
        payload: event,
        processed_at: new Date().toISOString(),
      })

      // Handle different event types
      switch (event.type) {
        case 'checkout.session.completed':
          await handleCheckoutCompleted(event.data.object)
          break

        case 'payment_intent.succeeded':
          await handlePaymentSucceeded(event.data.object)
          break

        case 'customer.subscription.updated':
          await handleSubscriptionUpdated(event.data.object)
          break

        case 'customer.subscription.deleted':
          await handleSubscriptionDeleted(event.data.object)
          break

        default:
          console.log(`Unhandled event type: ${event.type}`)
      }

      return new Response(
        JSON.stringify({ received: true }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    } catch (error) {
      console.error('Webhook handler error:', error)
      return new Response(
        JSON.stringify({ error: 'Webhook processing failed' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }
  },

  /**
   * POST /stripe/create-payment-intent
   * Create a payment intent for custom amounts (pledges/tips)
   */
  async createPaymentIntent(req: Request): Promise<Response> {
    try {
      const { amount, currency = 'usd', metadata } = await req.json()

      const response = await fetch('https://api.stripe.com/v1/payment_intents', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          amount: amount.toString(),
          currency,
          'automatic_payment_methods[enabled]': 'true',
          ...(metadata && Object.entries(metadata).reduce((acc, [key, value]) => {
            acc[`metadata[${key}]`] = value as string
            return acc
          }, {} as Record<string, string>)),
        }).toString(),
      })

      if (!response.ok) {
        const error = await response.text()
        console.error('Stripe API error:', error)
        return new Response(
          JSON.stringify({ error: 'Failed to create payment intent' }),
          { status: response.status, headers: { 'Content-Type': 'application/json' } }
        )
      }

      const paymentIntent = await response.json()

      return new Response(
        JSON.stringify({ clientSecret: paymentIntent.client_secret }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    } catch (error) {
      console.error('Create payment intent error:', error)
      return new Response(
        JSON.stringify({ error: 'Internal server error' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }
  },

  /**
   * POST /stripe/create-portal-session
   * Create a Stripe Customer Portal session for membership management
   */
  async createPortalSession(req: Request): Promise<Response> {
    try {
      const { customerId, returnUrl } = await req.json()

      if (!customerId) {
        return new Response(
          JSON.stringify({ error: 'Customer ID required' }),
          { status: 400, headers: { 'Content-Type': 'application/json' } }
        )
      }

      const response = await fetch('https://api.stripe.com/v1/billing_portal/sessions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          customer: customerId,
          return_url: returnUrl || 'http://localhost:3000/dashboard',
        }).toString(),
      })

      if (!response.ok) {
        const error = await response.text()
        console.error('Stripe API error:', error)
        return new Response(
          JSON.stringify({ error: 'Failed to create portal session' }),
          { status: response.status, headers: { 'Content-Type': 'application/json' } }
        )
      }

      const session = await response.json()

      return new Response(
        JSON.stringify({ url: session.url }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    } catch (error) {
      console.error('Create portal session error:', error)
      return new Response(
        JSON.stringify({ error: 'Internal server error' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }
  },
}

/**
 * Helper: Handle checkout.session.completed webhook
 */
async function handleCheckoutCompleted(session: any) {
  console.log('Processing checkout.session.completed:', session.id)

  const intent = session.metadata?.intent
  const userId = session.client_reference_id

  if (!userId) {
    console.error('No user ID found in checkout session')
    return
  }

  // Create purchase record
  const { data: purchase, error: purchaseError } = await supabase
    .from('purchases')
    .insert({
      user_id: userId,
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
    .single()

  if (purchaseError) {
    console.error('Error creating purchase record:', purchaseError)
    return
  }

  // Apply revenue splits
  try {
    const splitAmount = session.amount_total
    // Call splitEngine to distribute funds
    console.log(`Applying splits for purchase ${purchase.id}, amount: ${splitAmount}`)
    // TODO: Implement actual split logic
  } catch (error) {
    console.error('Error applying splits:', error)
  }

  // Handle different purchase intents
  switch (intent) {
    case 'ticket':
      await fulfillTicket(purchase.id, session.metadata)
      break
    case 'drop':
      await fulfillDrop(purchase.id, session.metadata)
      break
    case 'membership':
      await fulfillMembership(purchase.id, session.metadata)
      break
    default:
      console.log(`Unknown intent: ${intent}`)
  }
}

async function handlePaymentSucceeded(paymentIntent: any) {
  console.log('Processing payment_intent.succeeded:', paymentIntent.id)
  // Handle pledge confirmations, tips, etc.
}

async function handleSubscriptionUpdated(subscription: any) {
  console.log('Processing customer.subscription.updated:', subscription.id)
  // Update membership status
}

async function handleSubscriptionDeleted(subscription: any) {
  console.log('Processing customer.subscription.deleted:', subscription.id)
  // Cancel membership
}

async function fulfillTicket(purchaseId: string, metadata: any) {
  console.log('Fulfilling ticket for purchase:', purchaseId)
  // Create event_ticket record
}

async function fulfillDrop(purchaseId: string, metadata: any) {
  console.log('Fulfilling drop for purchase:', purchaseId)
  // Unlock locker content
}

async function fulfillMembership(purchaseId: string, metadata: any) {
  console.log('Fulfilling membership for purchase:', purchaseId)
  // Update fan_memberships table
}

