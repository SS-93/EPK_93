# Badge-Based Authentication & Treasury Production Migration Plan

**Date:** February 15, 2026
**Status:** Design & Implementation Plan
**Priority:** HIGH - Production Migration Required

---

## 🎯 Executive Summary

This document outlines the comprehensive plan for:

1. **Badge-Based Authentication System** - Universal login with role badges replacing separate logins
2. **Treasury Production Migration** - Moving from Stripe sandbox to production with full transaction logging

Both systems are designed to work together seamlessly while maintaining security and audit trails.

---

## Part 1: Badge-Based Authentication System

### 🔍 Current System Analysis

**Current Implementation:**
```typescript
// Current: Separate role-based signup
POST /auth/signup
{
  email, password,
  userData: {
    role: 'fan' | 'artist' | 'brand' | 'developer' | 'admin'
  }
}

// Current: Role stored in profiles table
profiles {
  id: UUID (user_id)
  role: user_role ENUM ('fan', 'artist', 'brand', 'developer', 'admin')
  onboarding_completed: BOOLEAN
}

// Current: MediaID per role
media_ids {
  user_uuid: UUID
  role: user_role ENUM
  interests: TEXT[]
  genre_preferences: TEXT[]
}
```

**Issues with Current System:**
1. ❌ **Single role per user** - User can only have one active role at a time
2. ❌ **Role switching complexity** - Requires database update to switch roles
3. ❌ **Separate MediaID per role** - Forces users to rebuild preferences for each role
4. ❌ **Onboarding friction** - Each role requires separate onboarding flow
5. ❌ **Dashboard access restrictions** - No easy way to access multiple dashboards
6. ⚠️ **Smart route guard works well** - But could be more flexible with badges

---

### ✨ Proposed Badge System Architecture

**Core Concept:** Universal login + Badge collection + Permission-based access

#### **1. Database Schema Changes**

**New Table: `user_badges`**
```sql
CREATE TABLE user_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_type TEXT NOT NULL, -- 'fan', 'artist', 'brand', 'developer', 'admin'

  -- Badge status
  is_active BOOLEAN DEFAULT true,
  is_primary BOOLEAN DEFAULT false, -- User's primary/default badge

  -- Badge-specific metadata
  badge_metadata JSONB DEFAULT '{}', -- Store badge-specific data

  -- Verification & approval
  verification_status TEXT DEFAULT 'pending', -- 'pending', 'verified', 'rejected'
  verified_by UUID REFERENCES auth.users(id),
  verified_at TIMESTAMPTZ,

  -- Permission levels (optional - for future granular permissions)
  permissions JSONB DEFAULT '[]', -- Array of permission strings

  -- Completion tracking
  onboarding_completed BOOLEAN DEFAULT false,
  onboarding_completed_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(user_id, badge_type)
);

-- Indexes
CREATE INDEX idx_user_badges_user_id ON user_badges(user_id);
CREATE INDEX idx_user_badges_active ON user_badges(user_id, is_active);
CREATE INDEX idx_user_badges_primary ON user_badges(user_id, is_primary);
```

**Update: `profiles` table**
```sql
-- Remove single role field, add primary_badge
ALTER TABLE profiles
  DROP COLUMN IF EXISTS role,
  ADD COLUMN primary_badge TEXT, -- Links to user_badges.badge_type
  ADD COLUMN all_badges TEXT[] DEFAULT '{}'; -- Cached array for quick lookups
```

**Update: `media_ids` table**
```sql
-- Keep role field but change strategy:
-- One MediaID per user (not per role) with role-specific preferences merged
ALTER TABLE media_ids
  ADD COLUMN role_preferences JSONB DEFAULT '{}';

-- Example role_preferences structure:
{
  "fan": {
    "interests": ["Music", "Art"],
    "genre_preferences": ["Hip Hop", "R&B"]
  },
  "artist": {
    "interests": ["Music", "Technology"],
    "genre_preferences": ["Hip Hop", "Electronic"]
  }
}
```

---

#### **2. Badge Acquisition Flow**

**Default Badge on Signup:**
```typescript
// Simplified signup - no role selection
POST /auth/signup
{
  email: "user@example.com",
  password: "secure123",
  display_name: "John Doe"
}

// Backend automatically grants FAN badge
async function createNewUser(email, password, display_name) {
  // 1. Create auth user
  const { data: user } = await supabase.auth.admin.createUser({
    email,
    password,
    user_metadata: { display_name }
  })

  // 2. Create profile (no role field)
  await supabase.from('profiles').insert({
    id: user.id,
    display_name,
    primary_badge: 'fan',
    all_badges: ['fan']
  })

  // 3. Grant FAN badge (default)
  await supabase.from('user_badges').insert({
    user_id: user.id,
    badge_type: 'fan',
    is_primary: true,
    is_active: true,
    verification_status: 'verified' // Auto-verify fan badge
  })

  // 4. Create MediaID (universal)
  await supabase.from('media_ids').insert({
    user_uuid: user.id,
    role_preferences: { fan: {} }
  })

  return user
}
```

**Badge Request Flow:**
```typescript
// User requests additional badge
POST /api/badges/request
{
  badge_type: 'artist',
  reason: 'I am a musician and want to upload my tracks',
  verification_data: {
    artist_name: 'DJ Example',
    social_links: { instagram: '@djexample' },
    sample_work: 'https://soundcloud.com/...'
  }
}

// Backend creates pending badge
async function requestBadge(userId, badgeType, verificationData) {
  // Check if badge already exists
  const existing = await supabase
    .from('user_badges')
    .select('*')
    .eq('user_id', userId)
    .eq('badge_type', badgeType)
    .single()

  if (existing) {
    throw new Error('Badge already exists')
  }

  // Create pending badge
  const badge = await supabase.from('user_badges').insert({
    user_id: userId,
    badge_type: badgeType,
    is_active: false, // Not active until verified
    verification_status: 'pending',
    badge_metadata: {
      request_reason: reason,
      verification_data: verificationData
    }
  })

  // Auto-verify certain badges (developer, brand)
  if (['developer', 'brand'].includes(badgeType)) {
    await approveBadge(badge.id, 'system')
  }

  // Admin approval required for artist badge
  if (badgeType === 'artist') {
    await notifyAdminsForApproval(badge.id)
  }

  return badge
}
```

**Badge Approval (Admin Dashboard):**
```typescript
// Admin approves badge request
POST /api/admin/badges/:badgeId/approve

async function approveBadge(badgeId, adminId) {
  // Update badge status
  const { data: badge } = await supabase
    .from('user_badges')
    .update({
      is_active: true,
      verification_status: 'verified',
      verified_by: adminId,
      verified_at: new Date()
    })
    .eq('id', badgeId)
    .select()
    .single()

  // Update user's all_badges cache
  await supabase.rpc('add_badge_to_user', {
    p_user_id: badge.user_id,
    p_badge_type: badge.badge_type
  })

  // Create role-specific entries (if needed)
  if (badge.badge_type === 'artist') {
    await supabase.from('artists').insert({
      user_id: badge.user_id,
      artist_name: badge.badge_metadata.verification_data.artist_name
    })
  }

  // Notify user
  await notifyUser(badge.user_id, `Your ${badge.badge_type} badge has been approved!`)

  return badge
}
```

---

#### **3. Badge Switching & Dashboard Access**

**Frontend Badge Manager:**
```typescript
// New hook: useBadges()
export function useBadges() {
  const { user } = useAuth()
  const [activeBadge, setActiveBadge] = useState<string | null>(null)
  const [badges, setBadges] = useState<UserBadge[]>([])

  useEffect(() => {
    if (!user) return

    // Fetch user's badges
    const loadBadges = async () => {
      const { data } = await supabase
        .from('user_badges')
        .select('*')
        .eq('user_id', user.id)
        .eq('is_active', true)
        .order('is_primary', { ascending: false })

      setBadges(data || [])

      // Set active badge to primary
      const primary = data?.find(b => b.is_primary)
      if (primary) {
        setActiveBadge(primary.badge_type)
      }
    }

    loadBadges()
  }, [user])

  // Switch active badge (in-memory, no DB update)
  const switchBadge = (badgeType: string) => {
    const badge = badges.find(b => b.badge_type === badgeType)
    if (!badge) {
      throw new Error('Badge not found or not active')
    }
    setActiveBadge(badgeType)

    // Update localStorage for persistence
    localStorage.setItem('activeBadge', badgeType)

    // Passport log the switch
    logEvent('badge.switched', {
      from_badge: activeBadge,
      to_badge: badgeType
    })
  }

  // Set primary badge (requires DB update)
  const setPrimaryBadge = async (badgeType: string) => {
    await supabase.rpc('set_primary_badge', {
      p_user_id: user.id,
      p_badge_type: badgeType
    })

    // Refresh badges
    loadBadges()
  }

  return {
    activeBadge,
    badges,
    switchBadge,
    setPrimaryBadge,
    hasBadge: (type: string) => badges.some(b => b.badge_type === type)
  }
}
```

**Updated SmartRouteGuard:**
```typescript
interface SmartRouteGuardProps {
  children: React.ReactNode
  requiredBadge?: string // Changed from allowedRoles
  requireAuth?: boolean
  requireOnboarding?: boolean
}

export const SmartRouteGuard: React.FC<SmartRouteGuardProps> = ({
  children,
  requiredBadge,
  requireAuth = true,
  requireOnboarding = true
}) => {
  const { user, loading: authLoading } = useAuth()
  const { activeBadge, badges, loading: badgesLoading } = useBadges()

  if (authLoading || badgesLoading) {
    return <LoadingState message="Loading..." />
  }

  if (requireAuth && !user) {
    return <Navigate to="/welcome" replace />
  }

  // Check if user has required badge
  if (requiredBadge) {
    const hasBadge = badges.some(b =>
      b.badge_type === requiredBadge &&
      b.is_active &&
      b.verification_status === 'verified'
    )

    if (!hasBadge) {
      return <Navigate to="/dashboard/badges" replace />
    }

    // Check badge onboarding
    const badge = badges.find(b => b.badge_type === requiredBadge)
    if (requireOnboarding && badge && !badge.onboarding_completed) {
      return <Navigate to={`/onboarding/${requiredBadge}`} replace />
    }
  }

  return <>{children}</>
}
```

**Badge Selector UI Component:**
```typescript
export function BadgeSelector() {
  const { activeBadge, badges, switchBadge } = useBadges()
  const navigate = useNavigate()

  const badgeIcons = {
    fan: '🎵',
    artist: '🎤',
    brand: '🏢',
    developer: '👨‍💻',
    admin: '⚙️'
  }

  return (
    <div className="badge-selector">
      {badges.map(badge => (
        <button
          key={badge.badge_type}
          className={`badge-button ${activeBadge === badge.badge_type ? 'active' : ''}`}
          onClick={() => {
            switchBadge(badge.badge_type)
            navigate(`/dashboard/${badge.badge_type}`)
          }}
        >
          <span className="badge-icon">{badgeIcons[badge.badge_type]}</span>
          <span className="badge-name">{badge.badge_type}</span>
          {badge.is_primary && <span className="badge-primary">★</span>}
        </button>
      ))}

      <button
        className="badge-button add-badge"
        onClick={() => navigate('/dashboard/badges/request')}
      >
        <span className="badge-icon">➕</span>
        <span className="badge-name">Request Badge</span>
      </button>
    </div>
  )
}
```

---

#### **4. Dashboard Routing Updates**

**New Routing Structure:**
```typescript
// OLD: /dashboard/artist (user must have artist role)
// NEW: /dashboard/artist (user must have artist badge)

const routes = [
  {
    path: '/dashboard/fan',
    element: (
      <SmartRouteGuard requiredBadge="fan">
        <FanDashboard />
      </SmartRouteGuard>
    )
  },
  {
    path: '/dashboard/artist',
    element: (
      <SmartRouteGuard requiredBadge="artist">
        <ArtistDashboard />
      </SmartRouteGuard>
    )
  },
  {
    path: '/dashboard/badges',
    element: (
      <SmartRouteGuard requireAuth>
        <BadgeManagementDashboard />
      </SmartRouteGuard>
    )
  },
  {
    path: '/dashboard/badges/request',
    element: (
      <SmartRouteGuard requireAuth>
        <BadgeRequestFlow />
      </SmartRouteGuard>
    )
  }
]
```

---

#### **5. Migration Strategy**

**Phase 1: Database Migration (1-2 days)**
```sql
-- Step 1: Create user_badges table
-- (SQL above)

-- Step 2: Migrate existing roles to badges
INSERT INTO user_badges (user_id, badge_type, is_primary, is_active, verification_status, onboarding_completed)
SELECT
  id as user_id,
  role as badge_type,
  true as is_primary,
  true as is_active,
  'verified' as verification_status,
  onboarding_completed
FROM profiles
WHERE role IS NOT NULL;

-- Step 3: Update profiles table
UPDATE profiles p
SET
  primary_badge = (SELECT badge_type FROM user_badges WHERE user_id = p.id AND is_primary = true),
  all_badges = ARRAY(SELECT badge_type FROM user_badges WHERE user_id = p.id AND is_active = true);

-- Step 4: Add stored procedures
CREATE OR REPLACE FUNCTION add_badge_to_user(p_user_id UUID, p_badge_type TEXT)
RETURNS void AS $$
BEGIN
  UPDATE profiles
  SET all_badges = array_append(all_badges, p_badge_type)
  WHERE id = p_user_id
  AND NOT (p_badge_type = ANY(all_badges));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION set_primary_badge(p_user_id UUID, p_badge_type TEXT)
RETURNS void AS $$
BEGIN
  -- Remove primary from all badges
  UPDATE user_badges
  SET is_primary = false
  WHERE user_id = p_user_id;

  -- Set new primary
  UPDATE user_badges
  SET is_primary = true
  WHERE user_id = p_user_id AND badge_type = p_badge_type;

  -- Update profiles cache
  UPDATE profiles
  SET primary_badge = p_badge_type
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql;
```

**Phase 2: Backend Updates (2-3 days)**
- Update auth routes to use badge system
- Create badge management endpoints
- Update profile routing logic
- Add badge request/approval flows
- Update Passport logging for badge switches

**Phase 3: Frontend Updates (3-4 days)**
- Create `useBadges()` hook
- Update `SmartRouteGuard` to use badges
- Build `BadgeSelector` component
- Build `BadgeManagementDashboard`
- Update all dashboard routes
- Update onboarding flows

**Phase 4: Testing (1-2 days)**
- Test badge acquisition flow
- Test badge switching
- Test dashboard access with badges
- Test admin approval workflow
- Test backward compatibility

**Total Timeline: 7-11 days**

---

### ✅ Badge System Benefits

1. ✅ **Multi-role users** - Users can hold multiple badges simultaneously
2. ✅ **Fast badge switching** - In-memory switch, no DB update needed
3. ✅ **Gradual badge collection** - Start as fan, add artist/brand later
4. ✅ **Verification workflow** - Admin approval for sensitive badges (artist)
5. ✅ **Permission granularity** - Each badge can have specific permissions
6. ✅ **Onboarding per badge** - Complete onboarding when acquiring badge
7. ✅ **Audit trail** - Badge requests/approvals tracked via Passport
8. ✅ **Smart route guard compatible** - Minimal changes to existing guard logic

---

## Part 2: Treasury Production Migration

### 🔍 Current Treasury System (Sandbox)

**Stripe Configuration:**
```env
# Current: Sandbox/Test Mode
STRIPE_SECRET_KEY=sk_test_51QOSKyRuRuEwBvxfLZYMp...
STRIPE_WEBHOOK_SECRET=whsec_...
```

**Payment Flow:**
1. Frontend creates checkout session → Stripe test mode
2. User completes payment → Stripe test webhook fires
3. Backend receives webhook → Creates purchase record
4. Fulfillment happens → Tickets created, splits calculated
5. Ledger entries created → Double-entry accounting
6. Passport logged → Immutable audit trail

**What's Working in Sandbox:**
- ✅ Checkout session creation
- ✅ Webhook handling with idempotency
- ✅ Purchase record creation
- ✅ Ticket generation with QR codes
- ✅ Revenue splits (70/20/10)
- ✅ Ledger entries (double-entry accounting)
- ⚠️ **Passport logging partial** - Not all transactions logged
- ⚠️ **Production keys not configured**

---

### 🎯 Production Migration Requirements

#### **1. Stripe Production Setup**

**Step 1: Get Production API Keys**
```bash
# Log into Stripe Dashboard → Developers → API Keys
# Copy:
# - Secret Key (sk_live_...)
# - Publishable Key (pk_live_...)
# - Webhook Signing Secret (whsec_...)
```

**Step 2: Update Environment Variables**
```env
# Production Environment (.env.production)
STRIPE_SECRET_KEY=sk_live_51QOSKyRuRuEwBvxfLZYMp...
STRIPE_PUBLISHABLE_KEY=pk_live_51QOSKyRuRuEwBvxfLZYMp...
STRIPE_WEBHOOK_SECRET=whsec_... # Production webhook secret
```

**Step 3: Configure Production Webhook**
```
Stripe Dashboard → Developers → Webhooks → Add Endpoint

Endpoint URL: https://api.yourdomain.com/stripe/webhook
Events to listen for:
  - checkout.session.completed
  - payment_intent.succeeded
  - payment_intent.payment_failed
  - customer.subscription.created
  - customer.subscription.updated
  - customer.subscription.deleted
  - invoice.paid
  - invoice.payment_failed
```

---

#### **2. Complete Passport Integration**

**Current Gap:** Not all treasury transactions log to Passport.

**Fix: Add Passport logging to all transaction points**

**File: `/server.js` - Update webhook handler**
```typescript
// BEFORE: Webhook handler doesn't log to Passport
async function handleCheckoutCompleted(session) {
  // Create purchase
  const purchase = await createPurchase(session)

  // Fulfill order
  await fulfillOrder(purchase)

  // Create ledger entries
  await createLedgerEntries(purchase)
}

// AFTER: Complete Passport integration
async function handleCheckoutCompleted(session) {
  const userId = session.metadata.userId
  const artistId = session.metadata.artistId
  const eventId = session.metadata.eventId

  // Create purchase
  const purchase = await createPurchase(session)

  // ✅ Log to Passport: Purchase completed
  await logPassportEvent({
    user_id: userId,
    event_type: 'treasury.purchase_completed',
    event_category: 'economic',
    entity_type: 'purchase',
    entity_id: purchase.id,
    metadata: {
      amount_cents: session.amount_total,
      currency: session.currency,
      payment_method: session.payment_method_types[0],
      event_id: eventId,
      artist_id: artistId,
      stripe_session_id: session.id,
      source: 'treasury'
    }
  })

  // Fulfill order
  const fulfillment = await fulfillOrder(purchase)

  // ✅ Log to Passport: Fulfillment (ticket created)
  if (fulfillment.intent === 'ticket') {
    await logPassportEvent({
      user_id: userId,
      event_type: 'concierto.ticket_purchased',
      event_category: 'economic',
      entity_type: 'ticket',
      entity_id: fulfillment.ticket_id,
      metadata: {
        event_id: eventId,
        ticket_tier: fulfillment.ticket_tier,
        ticket_number: fulfillment.ticket_number,
        purchase_id: purchase.id,
        amount_cents: session.amount_total,
        source: 'treasury'
      }
    })
  }

  // Create ledger entries (with splits)
  const ledgerEntries = await createLedgerEntries(purchase)

  // ✅ Log to Passport: Revenue splits
  for (const entry of ledgerEntries) {
    await logPassportEvent({
      user_id: entry.user_id,
      event_type: 'treasury.revenue_split_received',
      event_category: 'economic',
      entity_type: 'artist',
      entity_id: entry.user_id,
      metadata: {
        amount_cents: entry.amount_cents,
        split_percent: entry.metadata.split_percent,
        role: entry.metadata.role, // 'artist', 'platform', 'host'
        reason: entry.metadata.reason,
        event_id: eventId,
        purchase_id: purchase.id,
        ledger_entry_id: entry.id,
        source: 'treasury'
      }
    })
  }
}
```

**New Helper: Passport Logger**
```typescript
// File: /utils/passportLogger.ts
import { supabase } from './supabaseClient'

export async function logPassportEvent(event: {
  user_id: string
  event_type: string
  event_category: string
  entity_type: string
  entity_id: string
  metadata: Record<string, any>
}) {
  try {
    const { error } = await supabase
      .from('passport_entries')
      .insert({
        user_id: event.user_id,
        event_type: event.event_type,
        event_category: event.event_category,
        entity_type: event.entity_type,
        entity_id: event.entity_id,
        metadata: event.metadata,
        occurred_at: new Date().toISOString()
      })

    if (error) {
      console.error('Failed to log Passport event:', error)
      // Don't throw - logging failure shouldn't break transaction
    }
  } catch (err) {
    console.error('Passport logging error:', err)
  }
}
```

---

#### **3. Actual Ticketing System Verification**

**Requirements Checklist:**

**Ticket Generation:**
- [x] Ticket number format: `BKT-{YEAR}-{RANDOM}`
- [x] QR code generation with validation secret
- [x] Ticket tiers (General, VIP, Premium)
- [x] Perks storage (JSONB array)
- [x] Status tracking (active, redeemed, expired, cancelled)

**Ticket Validation:**
- [ ] **QR scanner implementation** (needs frontend)
- [ ] **Validation API endpoint** (needs backend)
- [ ] **Redemption flow** (mark as redeemed)
- [ ] **Double-scan prevention**

**Missing: Validation System**

**New Endpoint: Ticket Validation API**
```typescript
// File: /server.js
app.post('/api/tickets/validate', async (req, res) => {
  try {
    const { qr_code_data, validation_secret, event_id } = req.body

    // Fetch ticket
    const { data: ticket, error } = await supabase
      .from('event_tickets')
      .select('*')
      .eq('qr_code_data', qr_code_data)
      .eq('event_id', event_id)
      .single()

    if (error || !ticket) {
      return res.status(404).json({
        valid: false,
        error: 'Ticket not found'
      })
    }

    // Verify validation secret
    if (ticket.validation_secret !== validation_secret) {
      return res.status(403).json({
        valid: false,
        error: 'Invalid ticket'
      })
    }

    // Check if already redeemed
    if (ticket.status === 'redeemed') {
      return res.status(400).json({
        valid: false,
        error: 'Ticket already used',
        redeemed_at: ticket.redeemed_at
      })
    }

    // Check if expired
    if (ticket.status === 'expired') {
      return res.status(400).json({
        valid: false,
        error: 'Ticket expired'
      })
    }

    // Check event date
    const { data: event } = await supabase
      .from('events')
      .select('date')
      .eq('id', event_id)
      .single()

    const eventDate = new Date(event.date)
    const now = new Date()

    // Allow check-in 2 hours before event
    if (now < new Date(eventDate.getTime() - 2 * 60 * 60 * 1000)) {
      return res.status(400).json({
        valid: false,
        error: 'Too early to check in'
      })
    }

    // Mark as redeemed
    await supabase
      .from('event_tickets')
      .update({
        status: 'redeemed',
        redeemed_at: new Date().toISOString()
      })
      .eq('id', ticket.id)

    // Log to Passport
    await logPassportEvent({
      user_id: ticket.user_id,
      event_type: 'concierto.ticket_redeemed',
      event_category: 'interaction',
      entity_type: 'ticket',
      entity_id: ticket.id,
      metadata: {
        event_id: event_id,
        ticket_number: ticket.ticket_number,
        ticket_tier: ticket.ticket_tier,
        redeemed_at: new Date().toISOString(),
        source: 'treasury'
      }
    })

    return res.json({
      valid: true,
      ticket: {
        ticket_number: ticket.ticket_number,
        tier: ticket.ticket_tier,
        attendee_name: ticket.attendee_name,
        perks: ticket.perks
      }
    })
  } catch (error) {
    console.error('Ticket validation error:', error)
    return res.status(500).json({
      valid: false,
      error: 'Validation failed'
    })
  }
})
```

---

#### **4. Production Environment Checklist**

**Backend (.env.production):**
```env
# Supabase
SUPABASE_URL=https://your-production-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi... (production key)
SUPABASE_ANON_KEY=eyJhbGciOi... (production anon key)

# Stripe Production
STRIPE_SECRET_KEY=sk_live_...
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_WEBHOOK_SECRET=whsec_... (production webhook)

# App URLs
APP_URL=https://app.yourdomain.com
API_URL=https://api.yourdomain.com

# CORS
CORS_ORIGIN=https://app.yourdomain.com

# Node Environment
NODE_ENV=production
PORT=8000
```

**Frontend (.env.production):**
```env
REACT_APP_SUPABASE_URL=https://your-production-project.supabase.co
REACT_APP_SUPABASE_ANON_KEY=eyJhbGciOi...
REACT_APP_STRIPE_PUBLISHABLE_KEY=pk_live_...
REACT_APP_API_URL=https://api.yourdomain.com
```

**Database (Supabase Production):**
- [ ] Run all migrations
- [ ] Verify RLS policies
- [ ] Set up production backup schedule
- [ ] Configure connection pooling
- [ ] Enable performance insights
- [ ] Set up monitoring alerts

**Stripe Production:**
- [ ] Activate live mode
- [ ] Configure webhook endpoint
- [ ] Test webhook deliveries
- [ ] Set up fraud prevention
- [ ] Configure payment methods (cards, ACH, etc.)
- [ ] Set up subscription billing
- [ ] Configure tax calculations (if needed)

**Monitoring & Logging:**
- [ ] Set up error tracking (Sentry, LogRocket)
- [ ] Configure application logging
- [ ] Set up performance monitoring
- [ ] Create alerting rules (failed payments, webhook errors)
- [ ] Dashboard for treasury metrics

---

#### **5. UI Deployment Checklist**

**Build & Deploy:**
```bash
# Frontend Build
cd /Users/pks.ml/Desktop/93/my-app
npm run build
# Deploy build/ folder to CDN or hosting service

# Backend Deploy
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
# Deploy server.js to production server (e.g., Railway, Heroku, AWS)
# Ensure environment variables set
```

**DNS & SSL:**
- [ ] Configure DNS records
  - `app.yourdomain.com` → Frontend CDN
  - `api.yourdomain.com` → Backend server
- [ ] Set up SSL certificates (Let's Encrypt, Cloudflare)
- [ ] Enable HTTPS redirect

**Frontend Production:**
- [ ] Update Supabase URL in code
- [ ] Update Stripe publishable key
- [ ] Update API endpoint URLs
- [ ] Test authentication flow
- [ ] Test payment flow end-to-end

**Backend Production:**
- [ ] Deploy server.js
- [ ] Verify webhook URL accessible
- [ ] Test Stripe webhook delivery
- [ ] Test database connectivity
- [ ] Verify Passport logging works
- [ ] Test ticket validation endpoint

**Post-Deployment Testing:**
- [ ] Complete test purchase in production
- [ ] Verify webhook received
- [ ] Verify purchase record created
- [ ] Verify ticket generated
- [ ] Verify ledger entries created
- [ ] Verify Passport events logged
- [ ] Verify revenue splits calculated correctly
- [ ] Test ticket validation (QR scan)

---

### 🚨 Critical Production Considerations

**1. Idempotency (Already Implemented ✅)**
- Stripe webhook events deduplicated via `stripe_event_id`
- Prevents double-processing of payments

**2. Error Handling**
- [ ] Implement retry logic for failed webhooks
- [ ] Dead letter queue for unprocessable events
- [ ] Alert admins on payment failures
- [ ] Graceful degradation if Passport logging fails

**3. Security**
- [ ] Verify webhook signatures (already implemented ✅)
- [ ] Rate limit API endpoints
- [ ] Implement CSRF protection
- [ ] Secure ticket validation secrets
- [ ] PCI compliance review

**4. Data Integrity**
- [ ] Verify double-entry ledger balances
- [ ] Audit trail via Passport for all transactions
- [ ] Regular financial reconciliation
- [ ] Backup strategy for financial data

**5. Testing Strategy**
```bash
# Use Stripe Test Mode for staging
# Test scenarios:
# 1. Successful payment
# 2. Failed payment
# 3. Refund
# 4. Subscription creation
# 5. Subscription cancellation
# 6. Webhook delivery failure
# 7. Duplicate webhook delivery (test idempotency)
```

---

## 📋 Implementation Timeline

### **Phase 1: Badge System (7-11 days)**
- Days 1-2: Database migration, create user_badges table
- Days 3-5: Backend updates (badge API, approval workflow)
- Days 6-9: Frontend updates (useBadges hook, BadgeSelector UI)
- Days 10-11: Testing & documentation

### **Phase 2: Treasury Production Prep (3-5 days)**
- Day 1: Complete Passport integration in webhook handler
- Day 2: Build ticket validation API
- Day 3: Set up production Stripe account & webhook
- Day 4: Update environment variables, test in staging
- Day 5: Production deployment & smoke testing

### **Phase 3: Production Deployment (2-3 days)**
- Day 1: Deploy backend, verify webhook connectivity
- Day 2: Deploy frontend, end-to-end testing
- Day 3: Monitoring setup, final validation

**Total Timeline: 12-19 days**

---

## ✅ Success Criteria

**Badge System:**
- [ ] Users can have multiple badges simultaneously
- [ ] Badge switching works without DB updates
- [ ] Badge request/approval flow functional
- [ ] Admin dashboard for badge management
- [ ] All dashboards work with badge-based access
- [ ] Backward compatibility maintained

**Treasury Production:**
- [ ] Production Stripe keys configured
- [ ] Webhook receiving events successfully
- [ ] All transactions log to Passport
- [ ] Ticket validation API working
- [ ] Revenue splits calculated correctly
- [ ] Ledger balances verified
- [ ] No duplicate transactions
- [ ] QR code scanning works in production

---

## 📊 Metrics to Track

**Badge System:**
- Badge acquisition rate per type
- Average badges per user
- Badge switch frequency
- Badge approval time (for admin review)
- Onboarding completion rate per badge

**Treasury Production:**
- Transaction success rate
- Webhook delivery success rate
- Average payment processing time
- Ticket redemption rate
- Revenue split accuracy
- Passport event logging success rate

---

## 🔗 Next Steps

1. **Review this plan** - Confirm approach aligns with vision
2. **Prioritize phases** - Badge system first or treasury first?
3. **Assign tasks** - Break down work into sprints
4. **Set up staging environment** - Test before production
5. **Begin implementation** - Start with database migrations

**Recommended Order:**
1. **Treasury Production First** (critical, revenue-generating)
2. **Badge System Second** (UX improvement, can run parallel with production)

---

**Document Status:** ✅ Complete
**Ready for:** Implementation
**Estimated Effort:** 12-19 days total
**Risk Level:** Medium (production migration requires careful testing)

---

**Let me know when you're ready to start! 🚀**
