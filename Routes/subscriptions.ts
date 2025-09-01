import { serve } from "https://deno.land/std@0.177.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../middleware/cors.ts'
import { validateRequest } from '../middleware/validation.ts'
import { createErrorResponse, createSuccessResponse, createNotFoundResponse } from '../utils/responses.ts'

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY') ?? ''

export const subscriptionRoutes = {
  // POST /subscriptions/create-checkout
  async createCheckout(req: Request): Promise<Response> {
    try {
      const { artistId, tier, priceId, successUrl, cancelUrl } = await validateRequest(req, {
        artistId: 'string',
        tier: 'string',
        priceId: 'string',
        successUrl: 'string',
        cancelUrl: 'string'
      })

      // Get user from JWT
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) throw new Error('Invalid user session')

      // Verify artist exists
      const { data: artist, error: artistError } = await supabase
        .from('artists')
        .select('id, artist_name')
        .eq('id', artistId)
        .single()

      if (artistError || !artist) throw new Error('Artist not found')

      // Check if subscription already exists
      const { data: existingSubscription } = await supabase
        .from('subscriptions')
        .select('id, status')
        .eq('fan_id', user.id)
        .eq('artist_id', artistId)
        .single()

      if (existingSubscription && existingSubscription.status === 'active') {
        throw new Error('Already subscribed to this artist')
      }

      // Create Stripe Checkout session
      const stripeResponse = await fetch('https://api.stripe.com/v1/checkout/sessions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${stripeSecretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        body: new URLSearchParams({
          'mode': 'subscription',
          'line_items[0][price]': priceId,
          'line_items[0][quantity]': '1',
          'success_url': successUrl,
          'cancel_url': cancelUrl,
          'client_reference_id': user.id,
          'metadata[artist_id]': artistId,
          'metadata[tier]': tier,
          'customer_email': user.email || ''
        })
      })

      if (!stripeResponse.ok) {
        throw new Error('Failed to create Stripe checkout session')
      }

      const session = await stripeResponse.json()

      return createSuccessResponse({
        checkoutUrl: session.url,
        sessionId: session.id
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // GET /subscriptions/:userId
  async getUserSubscriptions(req: Request, userId: string): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) throw new Error('Invalid user session')

      // Users can only view their own subscriptions
      if (user.id !== userId) {
        throw new Error('Unauthorized to view these subscriptions')
      }

      const { data: subscriptions, error } = await supabase
        .from('subscriptions')
        .select(`
          id,
          tier,
          price_cents,
          status,
          stripe_subscription_id,
          current_period_start,
          current_period_end,
          cancel_at_period_end,
          created_at,
          artists (
            id,
            artist_name,
            banner_url
          )
        `)
        .eq('fan_id', userId)
        .order('created_at', { ascending: false })

      if (error) throw error

      return createSuccessResponse({
        subscriptions: subscriptions || []
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // PATCH /subscriptions/:id/cancel
  async cancelSubscription(req: Request, subscriptionId: string): Promise<Response> {
    try {
      const authHeader = req.headers.get('Authorization')
      if (!authHeader) throw new Error('No authorization header')

      const supabase = createClient(supabaseUrl, supabaseServiceKey, {
        global: { headers: { Authorization: authHeader } }
      })

      const { data: { user }, error: userError } = await supabase.auth.getUser()
      if (userError || !user) throw new Error('Invalid user session')

      // Get subscription and verify ownership
      const { data: subscription, error: subError } = await supabase
        .from('subscriptions')
        .select('id, fan_id, stripe_subscription_id, status')
        .eq('id', subscriptionId)
        .single()

      if (subError || !subscription) {
        return createNotFoundResponse('Subscription')
      }

      if (subscription.fan_id !== user.id) {
        throw new Error('Unauthorized to cancel this subscription')
      }

      if (subscription.status !== 'active') {
        throw new Error('Subscription is not active')
      }

      // Cancel subscription in Stripe
      const stripeResponse = await fetch(
        `https://api.stripe.com/v1/subscriptions/${subscription.stripe_subscription_id}`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${stripeSecretKey}`,
            'Content-Type': 'application/x-www-form-urlencoded'
          },
          body: new URLSearchParams({
            'cancel_at_period_end': 'true'
          })
        }
      )

      if (!stripeResponse.ok) {
        throw new Error('Failed to cancel subscription in Stripe')
      }

      // Update subscription in database
      const { error: updateError } = await supabase
        .from('subscriptions')
        .update({
          cancel_at_period_end: true,
          updated_at: new Date().toISOString()
        })
        .eq('id', subscriptionId)

      if (updateError) throw updateError

      return createSuccessResponse({
        message: 'Subscription will be cancelled at the end of the current period'
      })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  },

  // POST /webhooks/stripe
  async handleStripeWebhook(req: Request): Promise<Response> {
    try {
      const body = await req.text()
      const signature = req.headers.get('stripe-signature')

      if (!signature) {
        throw new Error('Missing stripe signature')
      }

      // Note: In production, you should verify the webhook signature
      // For now, we'll just parse the event
      const event = JSON.parse(body)

      const supabase = createClient(supabaseUrl, supabaseServiceKey)

      switch (event.type) {
        case 'checkout.session.completed':
          await handleCheckoutCompleted(event.data.object, supabase)
          break
        
        case 'invoice.payment_succeeded':
          await handlePaymentSucceeded(event.data.object, supabase)
          break
        
        case 'customer.subscription.deleted':
          await handleSubscriptionDeleted(event.data.object, supabase)
          break
        
        default:
          console.log(`Unhandled event type: ${event.type}`)
      }

      return createSuccessResponse({ received: true })

    } catch (error) {
      return createErrorResponse(error.message, 400)
    }
  }
}

async function handleCheckoutCompleted(session: any, supabase: any) {
  const userId = session.client_reference_id
  const artistId = session.metadata.artist_id
  const tier = session.metadata.tier
  const subscriptionId = session.subscription

  // Fetch Stripe subscription to persist price_cents
  const subscriptionResp = await fetch(`https://api.stripe.com/v1/subscriptions/${subscriptionId}?expand[]=items.data.price`, {
    headers: { 'Authorization': `Bearer ${stripeSecretKey}` }
  })
  if (!subscriptionResp.ok) throw new Error('Failed to fetch Stripe subscription')
  const subscription = await subscriptionResp.json()
  const priceCents = subscription?.items?.data?.[0]?.price?.unit_amount || null

  // Create or update subscription with price_cents
  await supabase
    .from('subscriptions')
    .upsert({
      fan_id: userId,
      artist_id: artistId,
      tier,
      price_cents: priceCents,
      status: 'active',
      stripe_subscription_id: subscriptionId,
      current_period_start: new Date().toISOString(),
      current_period_end: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
    }, { onConflict: 'fan_id,artist_id' })
}

async function handlePaymentSucceeded(invoice: any, supabase: any) {
  const subscriptionId = invoice.subscription
  const priceCents = invoice?.lines?.data?.[0]?.price?.unit_amount || null

  // Update subscription period
  const { data: subscription } = await supabase
    .from('subscriptions')
    .select('id')
    .eq('stripe_subscription_id', subscriptionId)
    .single()

  if (subscription) {
    await supabase
      .from('subscriptions')
      .update({
        status: 'active',
        ...(priceCents != null ? { price_cents: priceCents } : {}),
        current_period_start: new Date(invoice.period_start * 1000).toISOString(),
        current_period_end: new Date(invoice.period_end * 1000).toISOString()
      })
      .eq('id', subscription.id)
  }
}

async function handleSubscriptionDeleted(subscription: any, supabase: any) {
  // Mark subscription as canceled
  await supabase
    .from('subscriptions')
    .update({
      status: 'canceled',
      updated_at: new Date().toISOString()
    })
    .eq('stripe_subscription_id', subscription.id)
} 