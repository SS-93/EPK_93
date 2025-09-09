# 🔧 **Backend Implementation Plan for Event Management Feature**

**Author**: Lead Feature Architect  
**Target Role**: Backend Engineer  
**Project**: Buckets.media Event Management Integration  
**Version**: 1.0  
**Date**: December 2024  

---

## **Project Overview**
Integrate Event Management as a native feature within the existing Buckets.media platform, leveraging the current Supabase + PostgreSQL architecture. This will extend user capabilities with a "host badge" system allowing event creation and management while maintaining existing privacy and security standards.

---

## **Phase 1: Database Schema Extensions (Week 1)**

### **Task 1.1: Extend User Profiles for Host Privileges**

**Objective**: Add host capabilities to existing user system without creating new roles.

**Implementation**:
```sql
-- Migration: 003_event_host_privileges.sql
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS host_privileges JSONB DEFAULT '{
  "can_create_events": false,
  "max_concurrent_events": 0,
  "can_use_premium_features": false,
  "enabled_at": null,
  "enabled_by": null,
  "tier": "basic"
}';

-- Index for efficient host queries
CREATE INDEX IF NOT EXISTS idx_profiles_host_privileges 
ON profiles USING GIN(host_privileges) 
WHERE (host_privileges->>'can_create_events')::boolean = true;

-- Function to enable host privileges
CREATE OR REPLACE FUNCTION enable_host_privileges(
  user_id UUID,
  tier TEXT DEFAULT 'basic',
  max_events INTEGER DEFAULT 3,
  enabled_by_admin UUID DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  UPDATE profiles 
  SET host_privileges = jsonb_build_object(
    'can_create_events', true,
    'max_concurrent_events', max_events,
    'can_use_premium_features', tier = 'premium',
    'enabled_at', now(),
    'enabled_by', enabled_by_admin,
    'tier', tier
  )
  WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Acceptance Criteria**:
- ✅ Existing users unaffected (host_privileges defaults to disabled)
- ✅ Admin function to grant host privileges
- ✅ Efficient queries for host-enabled users
- ✅ Audit trail (enabled_by, enabled_at)

---

### **Task 1.2: Create Event Management Tables**

**Objective**: Design comprehensive event schema that integrates with existing MediaID system.

**Implementation**:
```sql
-- Migration: 004_event_management_schema.sql

-- Add event status enum
DO $$ BEGIN
    CREATE TYPE event_status AS ENUM (
      'draft', 'published', 'live', 'voting_closed', 
      'results_published', 'archived', 'cancelled'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Add join method enum  
DO $$ BEGIN
    CREATE TYPE join_method AS ENUM ('qr_code', 'sms', 'direct_link', 'invitation');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Main events table
CREATE TABLE IF NOT EXISTS events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  host_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Venue information
  venue_type TEXT CHECK (venue_type IN ('physical', 'virtual', 'hybrid')) DEFAULT 'virtual',
  venue_details JSONB DEFAULT '{}', -- {address, coordinates, virtual_link, etc}
  
  -- Timing
  start_time TIMESTAMP,
  end_time TIMESTAMP,
  voting_start_time TIMESTAMP,
  voting_end_time TIMESTAMP,
  
  -- Configuration
  voting_config JSONB DEFAULT '{
    "votes_per_user": 5,
    "voting_type": "single_round",
    "allow_multiple_votes_per_option": true,
    "tiebreaker_rule": "timestamp",
    "max_votes_per_option": null,
    "require_all_votes_used": false
  }',
  
  access_type TEXT CHECK (access_type IN ('public', 'private', 'invite_only')) DEFAULT 'public',
  status event_status DEFAULT 'draft',
  
  -- Join configuration
  join_config JSONB DEFAULT '{
    "qr_enabled": true,
    "sms_enabled": false,
    "direct_link": true,
    "require_registration": true,
    "collect_email": false,
    "collect_demographics": false
  }',
  
  -- Media and branding
  cover_image_url TEXT,
  branding JSONB DEFAULT '{}', -- colors, fonts, custom styling
  
  -- Statistics (updated via triggers)
  total_votes INTEGER DEFAULT 0,
  total_participants INTEGER DEFAULT 0,
  total_options INTEGER DEFAULT 0,
  
  -- MediaID integration
  target_interests TEXT[] DEFAULT '{}',
  privacy_level TEXT CHECK (privacy_level IN ('public', 'anonymous', 'private')) DEFAULT 'public',
  
  -- Metadata
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Event voting options
CREATE TABLE IF NOT EXISTS event_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  media_url TEXT, -- preview audio/video/image
  media_type content_type,
  
  -- Artist linkage (optional)
  artist_id UUID REFERENCES artists(id) ON DELETE SET NULL,
  artist_info JSONB DEFAULT '{}', -- for non-platform artists
  
  -- Voting stats (updated via triggers)
  vote_count INTEGER DEFAULT 0,
  unique_voters INTEGER DEFAULT 0,
  
  -- Display
  display_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Event participants (can be registered users or anonymous)
CREATE TABLE IF NOT EXISTS event_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  
  -- User identification (one of these will be set)
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  phone_number TEXT, -- for SMS users
  email TEXT,
  anonymous_id TEXT, -- for anonymous participation
  
  -- Registration details
  registration_method join_method DEFAULT 'qr_code',
  display_name TEXT,
  demographic_data JSONB DEFAULT '{}',
  
  -- Voting status
  votes_used INTEGER DEFAULT 0,
  max_votes INTEGER DEFAULT 5,
  last_vote_at TIMESTAMP,
  
  -- Privacy and consent
  privacy_settings JSONB DEFAULT '{
    "anonymous_participation": false,
    "data_sharing_consent": false,
    "marketing_consent": false
  }',
  
  -- Session tracking
  session_id TEXT,
  ip_address INET,
  user_agent TEXT,
  
  joined_at TIMESTAMP DEFAULT now(),
  
  -- Constraints
  UNIQUE(event_id, user_id),
  UNIQUE(event_id, phone_number),
  UNIQUE(event_id, anonymous_id),
  CHECK (
    (user_id IS NOT NULL AND phone_number IS NULL AND anonymous_id IS NULL) OR
    (user_id IS NULL AND phone_number IS NOT NULL AND anonymous_id IS NULL) OR
    (user_id IS NULL AND phone_number IS NULL AND anonymous_id IS NOT NULL)
  )
);

-- Individual votes
CREATE TABLE IF NOT EXISTS event_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  participant_id UUID REFERENCES event_participants(id) ON DELETE CASCADE,
  option_id UUID REFERENCES event_options(id) ON DELETE CASCADE,
  
  vote_weight INTEGER DEFAULT 1,
  vote_sequence INTEGER, -- order of votes from this participant
  
  -- Metadata for analytics
  voted_at TIMESTAMP DEFAULT now(),
  ip_address INET,
  user_agent TEXT,
  referrer TEXT,
  
  -- Ensure one vote per participant per option (if configured)
  UNIQUE(participant_id, option_id)
);

-- QR Code access tracking
CREATE TABLE IF NOT EXISTS event_qr_accesses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  qr_code_id TEXT, -- tracks which QR code was scanned
  
  accessed_at TIMESTAMP DEFAULT now(),
  ip_address INET,
  user_agent TEXT,
  referrer TEXT,
  
  -- Conversion tracking
  converted_to_participation BOOLEAN DEFAULT FALSE,
  participant_id UUID REFERENCES event_participants(id) ON DELETE SET NULL
);
```

**Acceptance Criteria**:
- ✅ All tables created with proper constraints and relationships
- ✅ Flexible participant system (registered, SMS, anonymous)
- ✅ Vote tracking with analytics metadata
- ✅ MediaID integration points prepared
- ✅ QR code access tracking ready

---

### **Task 1.3: Database Indexes and Performance Optimization**

**Implementation**:
```sql
-- Migration: 005_event_indexes.sql

-- Event queries
CREATE INDEX IF NOT EXISTS idx_events_host_status ON events(host_id, status);
CREATE INDEX IF NOT EXISTS idx_events_status_time ON events(status, start_time);
CREATE INDEX IF NOT EXISTS idx_events_interests ON events USING GIN(target_interests);
CREATE INDEX IF NOT EXISTS idx_events_public_live ON events(access_type, status) 
  WHERE access_type = 'public' AND status IN ('published', 'live');

-- Event options
CREATE INDEX IF NOT EXISTS idx_event_options_event ON event_options(event_id, display_order);
CREATE INDEX IF NOT EXISTS idx_event_options_artist ON event_options(artist_id) 
  WHERE artist_id IS NOT NULL;

-- Participants
CREATE INDEX IF NOT EXISTS idx_participants_event ON event_participants(event_id, joined_at);
CREATE INDEX IF NOT EXISTS idx_participants_user ON event_participants(user_id) 
  WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_participants_phone ON event_participants(phone_number) 
  WHERE phone_number IS NOT NULL;

-- Votes (critical for real-time leaderboards)
CREATE INDEX IF NOT EXISTS idx_votes_event_time ON event_votes(event_id, voted_at DESC);
CREATE INDEX IF NOT EXISTS idx_votes_option_count ON event_votes(option_id, voted_at);
CREATE INDEX IF NOT EXISTS idx_votes_participant ON event_votes(participant_id, voted_at);

-- QR tracking
CREATE INDEX IF NOT EXISTS idx_qr_access_event_time ON event_qr_accesses(event_id, accessed_at DESC);
```

---

### **Task 1.4: Database Functions and Triggers**

**Implementation**:
```sql
-- Migration: 006_event_functions.sql

-- Update statistics triggers
CREATE OR REPLACE FUNCTION update_event_stats()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Update total votes and participants
    UPDATE events 
    SET 
      total_votes = (
        SELECT COUNT(*) FROM event_votes WHERE event_id = NEW.event_id
      ),
      total_participants = (
        SELECT COUNT(DISTINCT participant_id) FROM event_votes WHERE event_id = NEW.event_id
      )
    WHERE id = NEW.event_id;
    
    -- Update option vote count
    UPDATE event_options 
    SET 
      vote_count = (
        SELECT COUNT(*) FROM event_votes WHERE option_id = NEW.option_id
      ),
      unique_voters = (
        SELECT COUNT(DISTINCT participant_id) FROM event_votes WHERE option_id = NEW.option_id
      )
    WHERE id = NEW.option_id;
    
  ELSIF TG_OP = 'DELETE' THEN
    -- Handle vote deletion (similar logic with OLD)
    UPDATE events 
    SET 
      total_votes = (
        SELECT COUNT(*) FROM event_votes WHERE event_id = OLD.event_id
      ),
      total_participants = (
        SELECT COUNT(DISTINCT participant_id) FROM event_votes WHERE event_id = OLD.event_id
      )
    WHERE id = OLD.event_id;
    
    UPDATE event_options 
    SET 
      vote_count = (
        SELECT COUNT(*) FROM event_votes WHERE option_id = OLD.option_id
      ),
      unique_voters = (
        SELECT COUNT(DISTINCT participant_id) FROM event_votes WHERE option_id = OLD.option_id
      )
    WHERE id = OLD.option_id;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Trigger for vote statistics
CREATE TRIGGER update_event_stats_trigger
  AFTER INSERT OR DELETE ON event_votes
  FOR EACH ROW EXECUTE FUNCTION update_event_stats();

-- Function to check voting eligibility
CREATE OR REPLACE FUNCTION check_voting_eligibility(
  p_event_id UUID,
  p_participant_id UUID,
  p_option_id UUID
) RETURNS JSONB AS $$
DECLARE
  event_record events%ROWTYPE;
  participant_record event_participants%ROWTYPE;
  votes_used INTEGER;
  max_votes INTEGER;
  existing_vote_count INTEGER;
BEGIN
  -- Get event details
  SELECT * INTO event_record FROM events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Event not found');
  END IF;
  
  -- Check event status
  IF event_record.status NOT IN ('live') THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Voting not active');
  END IF;
  
  -- Check timing
  IF now() < event_record.voting_start_time OR now() > event_record.voting_end_time THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Outside voting window');
  END IF;
  
  -- Get participant details
  SELECT * INTO participant_record FROM event_participants WHERE id = p_participant_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Participant not found');
  END IF;
  
  -- Check vote limits
  votes_used := participant_record.votes_used;
  max_votes := participant_record.max_votes;
  
  IF votes_used >= max_votes THEN
    RETURN jsonb_build_object('eligible', false, 'reason', 'Vote limit reached');
  END IF;
  
  -- Check if already voted for this option (if not allowed)
  IF NOT (event_record.voting_config->>'allow_multiple_votes_per_option')::boolean THEN
    SELECT COUNT(*) INTO existing_vote_count 
    FROM event_votes 
    WHERE participant_id = p_participant_id AND option_id = p_option_id;
    
    IF existing_vote_count > 0 THEN
      RETURN jsonb_build_object('eligible', false, 'reason', 'Already voted for this option');
    END IF;
  END IF;
  
  RETURN jsonb_build_object('eligible', true, 'remaining_votes', max_votes - votes_used);
END;
$$ LANGUAGE plpgsql;
```

---

## **Phase 2: API Endpoints Development (Week 2)**

### **Task 2.1: Extend Authentication Middleware**

**Objective**: Add host privilege checking to existing auth system.

**Implementation**:
```typescript
// middleware/eventAuth.ts
import { createClient } from '@supabase/supabase-js'
import { Request, Response, NextFunction } from 'express'

export interface AuthenticatedRequest extends Request {
  user?: {
    id: string
    role: string
    host_privileges?: {
      can_create_events: boolean
      max_concurrent_events: number
      can_use_premium_features: boolean
      tier: string
    }
  }
}

export const requireHostPrivileges = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    if (!req.user?.host_privileges?.can_create_events) {
      return res.status(403).json({
        success: false,
        error: 'Host privileges required. Contact admin to enable event hosting.',
        code: 'HOST_PRIVILEGES_REQUIRED'
      })
    }
    next()
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Authentication error',
      details: error.message
    })
  }
}

export const checkEventOwnership = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  try {
    const eventId = req.params.eventId || req.params.id
    const userId = req.user?.id
    
    const { data: event, error } = await supabase
      .from('events')
      .select('host_id, status')
      .eq('id', eventId)
      .single()
    
    if (error || !event) {
      return res.status(404).json({
        success: false,
        error: 'Event not found'
      })
    }
    
    if (event.host_id !== userId && req.user?.role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: 'Not authorized to modify this event'
      })
    }
    
    req.event = event
    next()
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Authorization error',
      details: error.message
    })
  }
}
```

---

### **Task 2.2: Event Management API Routes**

**Objective**: Create comprehensive CRUD operations for events.

**Implementation**:
```typescript
// Routes/events.ts
import { Router } from 'express'
import { requireAuth, requireHostPrivileges, checkEventOwnership } from '../middleware/eventAuth'
import { validateRequest } from '../middleware/validation'
import { createSuccessResponse, createErrorResponse } from '../utils/responses'

const router = Router()

// Event CRUD Operations
router.post('/create', requireAuth, requireHostPrivileges, async (req, res) => {
  try {
    const eventData = await validateRequest(req, {
      title: 'string',
      description: 'string',
      venue_type: 'string',
      start_time: 'string',
      end_time: 'string',
      voting_config: 'object',
      access_type: 'string',
      join_config: 'object'
    })

    // Check concurrent event limits
    const { count: activeEvents } = await supabase
      .from('events')
      .select('*', { count: 'exact', head: true })
      .eq('host_id', req.user.id)
      .in('status', ['draft', 'published', 'live'])

    if (activeEvents >= req.user.host_privileges.max_concurrent_events) {
      return res.status(400).json({
        success: false,
        error: `Maximum concurrent events (${req.user.host_privileges.max_concurrent_events}) reached`,
        code: 'EVENT_LIMIT_REACHED'
      })
    }

    const { data: event, error } = await supabase
      .from('events')
      .insert({
        ...eventData,
        host_id: req.user.id,
        status: 'draft'
      })
      .select()
      .single()

    if (error) throw error

    return createSuccessResponse({
      event,
      message: 'Event created successfully'
    }, 201)

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params
    const userId = req.user?.id

    let query = supabase
      .from('events')
      .select(`
        *,
        event_options (
          id, title, description, media_url, media_type,
          artist_id, vote_count, display_order
        ),
        profiles!events_host_id_fkey (
          display_name, avatar_url
        )
      `)
      .eq('id', id)

    // Apply access controls
    if (!userId) {
      query = query.eq('access_type', 'public')
    } else {
      query = query.or(`access_type.eq.public,host_id.eq.${userId}`)
    }

    const { data: event, error } = await query.single()

    if (error || !event) {
      return res.status(404).json({
        success: false,
        error: 'Event not found or access denied'
      })
    }

    // Add participation status if user is authenticated
    let participationStatus = null
    if (userId) {
      const { data: participant } = await supabase
        .from('event_participants')
        .select('votes_used, max_votes, joined_at')
        .eq('event_id', id)
        .eq('user_id', userId)
        .single()

      participationStatus = participant
    }

    return createSuccessResponse({
      event,
      participation_status: participationStatus
    })

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

router.put('/:id', requireAuth, checkEventOwnership, async (req, res) => {
  try {
    const { id } = req.params
    const updates = await validateRequest(req, {
      title: 'string',
      description: 'string',
      venue_details: 'object',
      voting_config: 'object',
      join_config: 'object'
    })

    // Prevent updates to live events
    if (req.event.status === 'live') {
      return res.status(400).json({
        success: false,
        error: 'Cannot modify live events'
      })
    }

    const { data: event, error } = await supabase
      .from('events')
      .update(updates)
      .eq('id', id)
      .select()
      .single()

    if (error) throw error

    return createSuccessResponse({
      event,
      message: 'Event updated successfully'
    })

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

router.post('/:id/publish', requireAuth, checkEventOwnership, async (req, res) => {
  try {
    const { id } = req.params

    // Validate event is ready for publishing
    const { data: options, error: optionsError } = await supabase
      .from('event_options')
      .select('id')
      .eq('event_id', id)

    if (optionsError || !options || options.length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Event must have at least 2 voting options to publish'
      })
    }

    const { data: event, error } = await supabase
      .from('events')
      .update({ 
        status: 'published',
        voting_start_time: req.body.voting_start_time || new Date().toISOString(),
        voting_end_time: req.body.voting_end_time
      })
      .eq('id', id)
      .select()
      .single()

    if (error) throw error

    // Generate QR code and join links
    const joinLink = `${process.env.APP_URL}/events/${id}/join`
    const qrCodeData = await generateQRCode(joinLink)

    return createSuccessResponse({
      event,
      join_link: joinLink,
      qr_code: qrCodeData,
      message: 'Event published successfully'
    })

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

export default router
```

---

### **Task 2.3: Event Options Management**

**Implementation**:
```typescript
// Routes/eventOptions.ts
router.post('/:eventId/options', requireAuth, checkEventOwnership, async (req, res) => {
  try {
    const { eventId } = req.params
    const optionData = await validateRequest(req, {
      title: 'string',
      description: 'string',
      media_url: 'string',
      media_type: 'string',
      artist_id: 'string' // optional
    })

    // Check if event allows new options
    if (req.event.status === 'live') {
      return res.status(400).json({
        success: false,
        error: 'Cannot add options to live events'
      })
    }

    // Get next display order
    const { data: lastOption } = await supabase
      .from('event_options')
      .select('display_order')
      .eq('event_id', eventId)
      .order('display_order', { ascending: false })
      .limit(1)
      .single()

    const nextOrder = (lastOption?.display_order || 0) + 1

    const { data: option, error } = await supabase
      .from('event_options')
      .insert({
        ...optionData,
        event_id: eventId,
        display_order: nextOrder
      })
      .select()
      .single()

    if (error) throw error

    // Update event options count
    await supabase.rpc('increment', {
      table_name: 'events',
      row_id: eventId,
      column_name: 'total_options'
    })

    return createSuccessResponse({
      option,
      message: 'Option added successfully'
    }, 201)

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

router.delete('/:eventId/options/:optionId', requireAuth, checkEventOwnership, async (req, res) => {
  try {
    const { eventId, optionId } = req.params

    // Check if event allows option removal
    if (req.event.status === 'live') {
      return res.status(400).json({
        success: false,
        error: 'Cannot remove options from live events'
      })
    }

    // Check if option has votes
    const { count: voteCount } = await supabase
      .from('event_votes')
      .select('*', { count: 'exact', head: true })
      .eq('option_id', optionId)

    if (voteCount > 0) {
      return res.status(400).json({
        success: false,
        error: 'Cannot remove option that has received votes'
      })
    }

    const { error } = await supabase
      .from('event_options')
      .delete()
      .eq('id', optionId)
      .eq('event_id', eventId)

    if (error) throw error

    return createSuccessResponse({
      message: 'Option removed successfully'
    })

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})
```

---

### **Task 2.4: Voting System API**

**Implementation**:
```typescript
// Routes/voting.ts
router.post('/:eventId/join', async (req, res) => {
  try {
    const { eventId } = req.params
    const joinData = await validateRequest(req, {
      phone_number: 'string', // optional
      email: 'string', // optional
      display_name: 'string', // optional
      privacy_settings: 'object'
    })

    // Get event details
    const { data: event, error: eventError } = await supabase
      .from('events')
      .select('*')
      .eq('id', eventId)
      .single()

    if (eventError || !event) {
      return res.status(404).json({
        success: false,
        error: 'Event not found'
      })
    }

    if (event.status !== 'published' && event.status !== 'live') {
      return res.status(400).json({
        success: false,
        error: 'Event not available for joining'
      })
    }

    // Create participant record
    const participantData = {
      event_id: eventId,
      user_id: req.user?.id || null,
      phone_number: joinData.phone_number || null,
      email: joinData.email || null,
      display_name: joinData.display_name || req.user?.display_name || null,
      registration_method: 'qr_code', // will be dynamic later
      max_votes: event.voting_config.votes_per_user || 5,
      privacy_settings: joinData.privacy_settings || {},
      ip_address: req.ip,
      user_agent: req.get('User-Agent')
    }

    // Handle anonymous participation
    if (!req.user?.id && !joinData.phone_number) {
      participantData.anonymous_id = `anon_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
    }

    const { data: participant, error } = await supabase
      .from('event_participants')
      .upsert(participantData, {
        onConflict: req.user?.id ? 'event_id,user_id' : 'event_id,phone_number'
      })
      .select()
      .single()

    if (error) throw error

    // Track QR access if applicable
    if (req.query.qr_code) {
      await supabase
        .from('event_qr_accesses')
        .insert({
          event_id: eventId,
          qr_code_id: req.query.qr_code,
          converted_to_participation: true,
          participant_id: participant.id,
          ip_address: req.ip,
          user_agent: req.get('User-Agent')
        })
    }

    return createSuccessResponse({
      participant,
      event: {
        id: event.id,
        title: event.title,
        voting_config: event.voting_config,
        status: event.status
      },
      message: 'Successfully joined event'
    }, 201)

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

router.post('/:eventId/vote', async (req, res) => {
  try {
    const { eventId } = req.params
    const { option_id, participant_id } = await validateRequest(req, {
      option_id: 'string',
      participant_id: 'string'
    })

    // Check voting eligibility using our database function
    const { data: eligibilityCheck, error: eligibilityError } = await supabase
      .rpc('check_voting_eligibility', {
        p_event_id: eventId,
        p_participant_id: participant_id,
        p_option_id: option_id
      })

    if (eligibilityError) throw eligibilityError

    if (!eligibilityCheck.eligible) {
      return res.status(400).json({
        success: false,
        error: eligibilityCheck.reason,
        code: 'VOTING_NOT_ALLOWED'
      })
    }

    // Cast the vote
    const { data: vote, error: voteError } = await supabase
      .from('event_votes')
      .insert({
        event_id: eventId,
        participant_id: participant_id,
        option_id: option_id,
        ip_address: req.ip,
        user_agent: req.get('User-Agent'),
        referrer: req.get('Referrer')
      })
      .select()
      .single()

    if (voteError) throw voteError

    // Update participant vote count
    await supabase
      .from('event_participants')
      .update({
        votes_used: supabase.sql`votes_used + 1`,
        last_vote_at: new Date().toISOString()
      })
      .eq('id', participant_id)

    // Get updated leaderboard
    const { data: leaderboard } = await supabase
      .from('event_options')
      .select('id, title, vote_count, unique_voters')
      .eq('event_id', eventId)
      .order('vote_count', { ascending: false })

    return createSuccessResponse({
      vote,
      remaining_votes: eligibilityCheck.remaining_votes - 1,
      leaderboard,
      message: 'Vote cast successfully'
    }, 201)

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

router.get('/:eventId/leaderboard', async (req, res) => {
  try {
    const { eventId } = req.params

    const { data: leaderboard, error } = await supabase
      .from('event_options')
      .select(`
        id, title, description, media_url,
        vote_count, unique_voters, display_order,
        artist_id,
        artists (
          artist_name, banner_url
        )
      `)
      .eq('event_id', eventId)
      .eq('is_active', true)
      .order('vote_count', { ascending: false })

    if (error) throw error

    // Get event status to determine if results should be shown
    const { data: event } = await supabase
      .from('events')
      .select('status, voting_end_time, total_votes, total_participants')
      .eq('id', eventId)
      .single()

    const showResults = event?.status === 'results_published' || 
                       (event?.status === 'voting_closed' && new Date() > new Date(event.voting_end_time))

    return createSuccessResponse({
      leaderboard: showResults ? leaderboard : leaderboard.map(option => ({
        ...option,
        vote_count: option.vote_count > 0 ? '•••' : 0 // Hide actual counts until results
      })),
      event_stats: {
        total_votes: event?.total_votes || 0,
        total_participants: event?.total_participants || 0,
        status: event?.status
      },
      results_available: showResults
    })

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})
```

---

## **Phase 3: QR Code System (Week 3)**

### **Task 3.1: QR Code Generation Service**

**Implementation**:
```typescript
// utils/qrCode.ts
import QRCode from 'qrcode'
import { createClient } from '@supabase/supabase-js'

export interface QRCodeData {
  id: string
  url: string
  data_url: string
  expires_at: Date
  scan_count: number
}

export const generateEventQRCode = async (
  eventId: string,
  options: {
    size?: number
    expires_in_hours?: number
    tracking_enabled?: boolean
  } = {}
): Promise<QRCodeData> => {
  const {
    size = 300,
    expires_in_hours = 24,
    tracking_enabled = true
  } = options

  // Generate unique QR code ID for tracking
  const qrId = `qr_${eventId}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  
  // Create the join URL with tracking
  const joinUrl = tracking_enabled 
    ? `${process.env.APP_URL}/events/${eventId}/join?qr_code=${qrId}&ref=qr`
    : `${process.env.APP_URL}/events/${eventId}/join`

  // Generate QR code image
  const qrDataUrl = await QRCode.toDataURL(joinUrl, {
    width: size,
    margin: 2,
    color: {
      dark: '#000000',
      light: '#FFFFFF'
    },
    errorCorrectionLevel: 'M'
  })

  // Store QR code metadata
  const expiresAt = new Date()
  expiresAt.setHours(expiresAt.getHours() + expires_in_hours)

  const qrData: QRCodeData = {
    id: qrId,
    url: joinUrl,
    data_url: qrDataUrl,
    expires_at: expiresAt,
    scan_count: 0
  }

  return qrData
}

export const trackQRCodeAccess = async (
  qrCodeId: string,
  eventId: string,
  metadata: {
    ip_address?: string
    user_agent?: string
    referrer?: string
  }
) => {
  try {
    await supabase
      .from('event_qr_accesses')
      .insert({
        event_id: eventId,
        qr_code_id: qrCodeId,
        ip_address: metadata.ip_address,
        user_agent: metadata.user_agent,
        referrer: metadata.referrer
      })
  } catch (error) {
    console.error('QR tracking error:', error)
    // Don't throw - tracking failures shouldn't break the flow
  }
}
```

---

### **Task 3.2: QR Code API Endpoints**

**Implementation**:
```typescript
// Routes/qr.ts
router.post('/generate/:eventId', requireAuth, checkEventOwnership, async (req, res) => {
  try {
    const { eventId } = req.params
    const { size, expires_in_hours } = req.body

    const qrData = await generateEventQRCode(eventId, {
      size: size || 300,
      expires_in_hours: expires_in_hours || 24,
      tracking_enabled: true
    })

    return createSuccessResponse({
      qr_code: qrData,
      message: 'QR code generated successfully'
    })

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})

router.get('/track/:qrCodeId', async (req, res) => {
  try {
    const { qrCodeId } = req.params

    // This endpoint is called when QR codes are scanned
    // Extract event ID from QR code ID pattern
    const eventId = qrCodeId.split('_')[1]

    await trackQRCodeAccess(qrCodeId, eventId, {
      ip_address: req.ip,
      user_agent: req.get('User-Agent'),
      referrer: req.get('Referrer')
    })

    // Redirect to event join page
    res.redirect(`/events/${eventId}/join?qr_code=${qrCodeId}&ref=qr`)

  } catch (error) {
    res.status(400).json({
      success: false,
      error: 'Invalid QR code'
    })
  }
})

router.get('/analytics/:eventId', requireAuth, checkEventOwnership, async (req, res) => {
  try {
    const { eventId } = req.params

    const { data: qrAnalytics, error } = await supabase
      .from('event_qr_accesses')
      .select(`
        qr_code_id,
        accessed_at,
        converted_to_participation,
        COUNT(*) as scan_count
      `)
      .eq('event_id', eventId)
      .group('qr_code_id, accessed_at, converted_to_participation')
      .order('accessed_at', { ascending: false })

    if (error) throw error

    // Calculate conversion rates
    const totalScans = qrAnalytics.length
    const conversions = qrAnalytics.filter(a => a.converted_to_participation).length
    const conversionRate = totalScans > 0 ? (conversions / totalScans) * 100 : 0

    return createSuccessResponse({
      analytics: qrAnalytics,
      summary: {
        total_scans: totalScans,
        conversions: conversions,
        conversion_rate: conversionRate
      }
    })

  } catch (error) {
    return createErrorResponse(error.message, 400)
  }
})
```

---

## **Phase 4: Real-time Features & WebSocket Integration (Week 4)**

### **Task 4.1: Real-time Leaderboard Updates**

**Implementation**:
```typescript
// services/realtime.ts
import { Server as SocketIOServer } from 'socket.io'
import { createClient } from '@supabase/supabase-js'

export const setupEventRealtime = (io: SocketIOServer) => {
  // Create namespace for event updates
  const eventNamespace = io.of('/events')

  eventNamespace.on('connection', (socket) => {
    console.log('Client connected to events namespace:', socket.id)

    // Join event room for updates
    socket.on('join_event', (eventId: string) => {
      socket.join(`event_${eventId}`)
      console.log(`Client ${socket.id} joined event ${eventId}`)
    })

    // Leave event room
    socket.on('leave_event', (eventId: string) => {
      socket.leave(`event_${eventId}`)
    })

    socket.on('disconnect', () => {
      console.log('Client disconnected:', socket.id)
    })
  })

  // Set up Supabase real-time subscription for vote updates
  const supabase = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  )

  supabase
    .channel('event_votes')
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'event_votes'
      },
      async (payload) => {
        try {
          // Get updated leaderboard for the event
          const eventId = payload.new.event_id
          
          const { data: leaderboard } = await supabase
            .from('event_options')
            .select('id, title, vote_count, unique_voters')
            .eq('event_id', eventId)
            .order('vote_count', { ascending: false })

          const { data: eventStats } = await supabase
            .from('events')
            .select('total_votes, total_participants')
            .eq('id', eventId)
            .single()

          // Broadcast to all clients in the event room
          eventNamespace.to(`event_${eventId}`).emit('leaderboard_update', {
            event_id: eventId,
            leaderboard,
            stats: eventStats,
            timestamp: new Date().toISOString()
          })

          // Also broadcast the new vote event
          eventNamespace.to(`event_${eventId}`).emit('new_vote', {
            event_id: eventId,
            option_id: payload.new.option_id,
            timestamp: payload.new.voted_at
          })

        } catch (error) {
          console.error('Real-time update error:', error)
        }
      }
    )
    .subscribe()

  return eventNamespace
}
```

---

### **Task 4.2: Event Status Management**

**Implementation**:
```typescript
// services/eventStatus.ts
export const updateEventStatus = async (
  eventId: string,
  newStatus: string,
  metadata: any = {}
) => {
  try {
    const { data: event, error } = await supabase
      .from('events')
      .update({
        status: newStatus,
        ...metadata
      })
      .eq('id', eventId)
      .select()
      .single()

    if (error) throw error

    // Broadcast status change to all connected clients
    io.of('/events').to(`event_${eventId}`).emit('event_status_change', {
      event_id: eventId,
      status: newStatus,
      event: event,
      timestamp: new Date().toISOString()
    })

    // Handle status-specific logic
    switch (newStatus) {
      case 'live':
        await handleEventGoLive(eventId)
        break
      case 'voting_closed':
        await handleVotingClosed(eventId)
        break
      case 'results_published':
        await handleResultsPublished(eventId)
        break
    }

    return event
  } catch (error) {
    console.error('Event status update error:', error)
    throw error
  }
}

const handleEventGoLive = async (eventId: string) => {
  // Future: Send notifications to interested users
  // Future: Update MediaID engagement logs
  console.log(`Event ${eventId} is now live`)
}

const handleVotingClosed = async (eventId: string) => {
  // Calculate final results
  const { data: results } = await supabase
    .from('event_options')
    .select('*')
    .eq('event_id', eventId)
    .order('vote_count', { ascending: false })

  // Store final results
  await supabase
    .from('events')
    .update({
      metadata: supabase.sql`metadata || ${JSON.stringify({ final_results: results })}`
    })
    .eq('id', eventId)
}

const handleResultsPublished = async (eventId: string) => {
  // Future: Generate recap pages
  // Future: Send result notifications
  console.log(`Results published for event ${eventId}`)
}
```

---

## **Phase 5: Testing & Integration (Week 5)**

### **Task 5.1: Unit Test Suite**

**Implementation**:
```typescript
// tests/events.test.ts
import { describe, test, expect, beforeEach, afterEach } from '@jest/globals'
import { createClient } from '@supabase/supabase-js'
import request from 'supertest'
import app from '../app'

describe('Event Management API', () => {
  let testUser: any
  let authToken: string
  
  beforeEach(async () => {
    // Create test user with host privileges
    testUser = await createTestUser({
      role: 'artist',
      host_privileges: {
        can_create_events: true,
        max_concurrent_events: 5,
        can_use_premium_features: false,
        tier: 'basic'
      }
    })
    authToken = generateTestToken(testUser.id)
  })

  afterEach(async () => {
    await cleanupTestData()
  })

  describe('POST /api/events/create', () => {
    test('should create event successfully with valid data', async () => {
      const eventData = {
        title: 'Test Music Vote',
        description: 'Choose my next single',
        venue_type: 'virtual',
        start_time: new Date(Date.now() + 86400000).toISOString(), // tomorrow
        end_time: new Date(Date.now() + 90000000).toISOString(),
        voting_config: {
          votes_per_user: 5,
          voting_type: 'single_round'
        },
        access_type: 'public'
      }

      const response = await request(app)
        .post('/api/events/create')
        .set('Authorization', `Bearer ${authToken}`)
        .send(eventData)
        .expect(201)

      expect(response.body.success).toBe(true)
      expect(response.body.data.event.title).toBe(eventData.title)
      expect(response.body.data.event.host_id).toBe(testUser.id)
      expect(response.body.data.event.status).toBe('draft')
    })

    test('should reject creation without host privileges', async () => {
      const regularUser = await createTestUser({ role: 'fan' })
      const regularToken = generateTestToken(regularUser.id)

      const response = await request(app)
        .post('/api/events/create')
        .set('Authorization', `Bearer ${regularToken}`)
        .send({ title: 'Test Event' })
        .expect(403)

      expect(response.body.success).toBe(false)
      expect(response.body.code).toBe('HOST_PRIVILEGES_REQUIRED')
    })

    test('should enforce concurrent event limits', async () => {
      // Create maximum allowed events
      for (let i = 0; i < testUser.host_privileges.max_concurrent_events; i++) {
        await createTestEvent(testUser.id, { status: 'published' })
      }

      const response = await request(app)
        .post('/api/events/create')
        .set('Authorization', `Bearer ${authToken}`)
        .send({ title: 'Over Limit Event' })
        .expect(400)

      expect(response.body.code).toBe('EVENT_LIMIT_REACHED')
    })
  })

  describe('POST /api/events/:id/vote', () => {
    let testEvent: any
    let testParticipant: any

    beforeEach(async () => {
      testEvent = await createTestEvent(testUser.id, { status: 'live' })
      testParticipant = await createTestParticipant(testEvent.id)
      await createTestEventOptions(testEvent.id, 3)
    })

    test('should cast vote successfully', async () => {
      const { data: options } = await supabase
        .from('event_options')
        .select('id')
        .eq('event_id', testEvent.id)
        .limit(1)

      const response = await request(app)
        .post(`/api/events/${testEvent.id}/vote`)
        .send({
          option_id: options[0].id,
          participant_id: testParticipant.id
        })
        .expect(201)

      expect(response.body.success).toBe(true)
      expect(response.body.data.vote.option_id).toBe(options[0].id)
      expect(response.body.data.remaining_votes).toBe(4) // 5 - 1
    })

    test('should reject vote when limit reached', async () => {
      // Use all votes
      const { data: options } = await supabase
        .from('event_options')
        .select('id')
        .eq('event_id', testEvent.id)

      for (let i = 0; i < 5; i++) {
        await createTestVote(testEvent.id, testParticipant.id, options[i % options.length].id)
      }

      const response = await request(app)
        .post(`/api/events/${testEvent.id}/vote`)
        .send({
          option_id: options[0].id,
          participant_id: testParticipant.id
        })
        .expect(400)

      expect(response.body.code).toBe('VOTING_NOT_ALLOWED')
    })
  })
})

// Test utilities
const createTestUser = async (userData: any) => {
  const { data: user } = await supabase.auth.admin.createUser({
    email: `test-${Date.now()}@example.com`,
    password: 'testpassword123',
    user_metadata: userData
  })
  
  await supabase
    .from('profiles')
    .insert({
      id: user.user.id,
      ...userData
    })
    
  return user.user
}

const createTestEvent = async (hostId: string, eventData: any = {}) => {
  const { data: event } = await supabase
    .from('events')
    .insert({
      title: 'Test Event',
      host_id: hostId,
      status: 'draft',
      ...eventData
    })
    .select()
    .single()
    
  return event
}
```

---

### **Task 5.2: Database Migration Tests**

**Implementation**:
```typescript
// tests/migrations.test.ts
describe('Database Migrations', () => {
  test('should create all event tables successfully', async () => {
    const tables = ['events', 'event_options', 'event_participants', 'event_votes', 'event_qr_accesses']
    
    for (const table of tables) {
      const { data, error } = await supabase
        .from(table)
        .select('*')
        .limit(1)
      
      expect(error).toBeNull()
    }
  })

  test('should enforce foreign key constraints', async () => {
    // Try to insert event option without valid event
    const { error } = await supabase
      .from('event_options')
      .insert({
        event_id: '00000000-0000-0000-0000-000000000000',
        title: 'Invalid Option'
      })
    
    expect(error).toBeTruthy()
    expect(error.code).toBe('23503') // Foreign key violation
  })

  test('should update statistics via triggers', async () => {
    const event = await createTestEvent()
    const participant = await createTestParticipant(event.id)
    const option = await createTestEventOption(event.id)
    
    // Cast a vote
    await supabase
      .from('event_votes')
      .insert({
        event_id: event.id,
        participant_id: participant.id,
        option_id: option.id
      })
    
    // Check that statistics were updated
    const { data: updatedEvent } = await supabase
      .from('events')
      .select('total_votes, total_participants')
      .eq('id', event.id)
      .single()
    
    expect(updatedEvent.total_votes).toBe(1)
    expect(updatedEvent.total_participants).toBe(1)
    
    const { data: updatedOption } = await supabase
      .from('event_options')
      .select('vote_count, unique_voters')
      .eq('id', option.id)
      .single()
    
    expect(updatedOption.vote_count).toBe(1)
    expect(updatedOption.unique_voters).toBe(1)
  })
})
```

---

## **Phase 6: Documentation & Deployment Preparation (Week 6)**

### **Task 6.1: API Documentation**

**Implementation**: Create comprehensive OpenAPI/Swagger documentation:

```yaml
# docs/events-api.yaml
openapi: 3.0.0
info:
  title: Buckets Events API
  version: 1.0.0
  description: Event Management and Voting Platform API

paths:
  /api/events/create:
    post:
      summary: Create a new event
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateEventRequest'
      responses:
        201:
          description: Event created successfully
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/EventResponse'
        403:
          description: Host privileges required
        400:
          description: Validation error

components:
  schemas:
    CreateEventRequest:
      type: object
      required:
        - title
        - venue_type
      properties:
        title:
          type: string
          description: Event title
        description:
          type: string
        venue_type:
          type: string
          enum: [physical, virtual, hybrid]
        voting_config:
          $ref: '#/components/schemas/VotingConfig'
    
    VotingConfig:
      type: object
      properties:
        votes_per_user:
          type: integer
          minimum: 1
          maximum: 10
          default: 5
        voting_type:
          type: string
          enum: [single_round]
          default: single_round
```

---

### **Task 6.2: Deployment Configuration**

**Implementation**:
```typescript
// Deploy configuration
// docker-compose.yml for development
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: development
      POSTGRES_DB: buckets_events
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database/migrations:/docker-entrypoint-initdb.d

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  app:
    build: .
    environment:
      - NODE_ENV=development
      - DATABASE_URL=postgresql://postgres:development@postgres:5432/buckets_events
      - REDIS_URL=redis://redis:6379
    ports:
      - "3001:3001"
    depends_on:
      - postgres
      - redis

volumes:
  postgres_data:
```

---

## **🎯 Implementation Checklist**

### **Database Foundation**
- [ ] Add host_privileges column to profiles table
- [ ] Create event management tables with proper constraints
- [ ] Set up indexes for performance
- [ ] Create database functions and triggers
- [ ] Write migration rollback scripts

### **API Development** 
- [ ] Extend authentication middleware for host privileges
- [ ] Implement event CRUD operations
- [ ] Build voting system endpoints
- [ ] Create QR code generation service
- [ ] Add real-time WebSocket integration

### **Testing & Quality**
- [ ] Unit tests for all endpoints (>80% coverage)
- [ ] Integration tests for voting flow
- [ ] Database migration tests
- [ ] Performance testing for concurrent voting
- [ ] Security penetration testing

### **Documentation & Deployment**
- [ ] Complete API documentation
- [ ] Database schema documentation
- [ ] Deployment scripts and configuration
- [ ] Monitoring and logging setup
- [ ] Error handling and recovery procedures

---

## **🔧 Development Guidelines**

### **Code Standards**
- Use TypeScript with strict mode enabled
- Follow existing project patterns and naming conventions
- Implement comprehensive error handling
- Add detailed logging for debugging
- Write tests for all new functionality

### **Security Requirements**
- Validate all input data
- Use parameterized queries (Supabase handles this)
- Implement rate limiting on voting endpoints
- Audit all database access patterns
- Follow principle of least privilege

### **Performance Considerations**
- Index all foreign keys and frequently queried columns
- Use database triggers for real-time statistics
- Implement efficient pagination for large datasets
- Cache frequent queries appropriately
- Monitor query performance and optimize as needed

---

**End of Backend Implementation Plan**

This comprehensive implementation plan provides everything needed to build the Event Management feature as an integrated part of the Buckets.media platform. The phased approach allows for iterative development and testing while maintaining the existing system's integrity and performance.











