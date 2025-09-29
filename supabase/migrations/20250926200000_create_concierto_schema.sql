-- ===============================================
-- CONCIERTO: EVENT MANAGEMENT & VOTING SYSTEM
-- Phase 1: Database Schema for buckets.media/events/
-- ===============================================

-- Events table - Core event management
CREATE TABLE IF NOT EXISTS events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Basic event info
  title TEXT NOT NULL,
  description TEXT,
  cover_image_url TEXT,

  -- Timing
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ NOT NULL,
  voting_opens_at TIMESTAMPTZ,
  voting_closes_at TIMESTAMPTZ,

  -- Event configuration
  shareable_code TEXT UNIQUE NOT NULL, -- For QR codes and links
  max_votes_per_participant INTEGER DEFAULT 5,
  allow_multiple_votes_per_artist BOOLEAN DEFAULT false,

  -- Ownership and status
  host_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'live', 'completed', 'cancelled')),

  -- CRM and analytics
  analytics_data JSONB DEFAULT '{}',
  settings JSONB DEFAULT '{}', -- Custom event settings

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Event artists - Artists participating in events
CREATE TABLE IF NOT EXISTS event_artists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  artist_profile_id UUID NOT NULL REFERENCES artist_profiles(id) ON DELETE CASCADE,

  -- Registration details
  registration_status TEXT NOT NULL DEFAULT 'invited' CHECK (registration_status IN ('invited', 'confirmed', 'declined', 'withdrawn')),
  registration_token TEXT UNIQUE, -- For secure artist registration links

  -- Event-specific artist data
  event_bio TEXT, -- Custom bio for this event
  featured_track_id UUID REFERENCES content_items(id), -- Artist's featured track for this event
  social_links JSONB DEFAULT '{}',
  display_order INTEGER DEFAULT 0,

  -- Analytics
  vote_count INTEGER DEFAULT 0,
  engagement_data JSONB DEFAULT '{}',

  registered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(event_id, artist_profile_id)
);

-- Event participants - Users who vote (pre-signup capture)
CREATE TABLE IF NOT EXISTS event_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,

  -- Participant data (pre-signup capture)
  email TEXT,
  phone TEXT,
  name TEXT,

  -- Voting session
  vote_token TEXT UNIQUE NOT NULL, -- Unique session token
  total_votes_cast INTEGER DEFAULT 0,
  votes_remaining INTEGER,

  -- Registration source tracking
  registration_source TEXT, -- 'qr', 'link', 'referral', 'direct'
  referrer_data JSONB DEFAULT '{}',

  -- Engagement tracking
  session_duration_seconds INTEGER DEFAULT 0,
  interactions_count INTEGER DEFAULT 0,
  engagement_data JSONB DEFAULT '{}',

  -- Consent and preferences
  marketing_consent BOOLEAN DEFAULT false,
  platform_invite_sent BOOLEAN DEFAULT false,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Votes - Individual vote records
CREATE TABLE IF NOT EXISTS event_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  participant_id UUID NOT NULL REFERENCES event_participants(id) ON DELETE CASCADE,
  event_artist_id UUID NOT NULL REFERENCES event_artists(id) ON DELETE CASCADE,

  -- Vote metadata
  vote_weight INTEGER DEFAULT 1, -- For future weighted voting
  vote_source TEXT DEFAULT 'web', -- 'web', 'qr', 'embedded'
  device_info JSONB DEFAULT '{}',

  created_at TIMESTAMPTZ DEFAULT now(),

  -- Prevent duplicate votes if not allowing multiple per artist
  UNIQUE(event_id, participant_id, event_artist_id)
);

-- CRM Follow-ups - Post-event engagement
CREATE TABLE IF NOT EXISTS event_follow_ups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  participant_id UUID NOT NULL REFERENCES event_participants(id) ON DELETE CASCADE,

  -- Follow-up campaign details
  follow_up_type TEXT NOT NULL, -- 'platform_invite', 'artist_track_share', 'event_recap', 'next_event'
  campaign_id TEXT, -- For grouping follow-ups

  -- Content
  subject TEXT,
  content TEXT,
  artist_track_id UUID REFERENCES content_items(id), -- If sharing specific track

  -- Delivery tracking
  sent_at TIMESTAMPTZ,
  opened_at TIMESTAMPTZ,
  clicked_at TIMESTAMPTZ,
  conversion_data JSONB DEFAULT '{}',

  created_at TIMESTAMPTZ DEFAULT now()
);

-- ===============================================
-- INDEXES FOR PERFORMANCE
-- ===============================================

-- Event indexes
CREATE INDEX IF NOT EXISTS idx_events_host_user_id ON events(host_user_id);
CREATE INDEX IF NOT EXISTS idx_events_shareable_code ON events(shareable_code);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
CREATE INDEX IF NOT EXISTS idx_events_dates ON events(start_date, end_date);

-- Event artists indexes
CREATE INDEX IF NOT EXISTS idx_event_artists_event_id ON event_artists(event_id);
CREATE INDEX IF NOT EXISTS idx_event_artists_profile_id ON event_artists(artist_profile_id);
CREATE INDEX IF NOT EXISTS idx_event_artists_status ON event_artists(registration_status);
CREATE INDEX IF NOT EXISTS idx_event_artists_vote_count ON event_artists(vote_count DESC);

-- Participants indexes
CREATE INDEX IF NOT EXISTS idx_event_participants_event_id ON event_participants(event_id);
CREATE INDEX IF NOT EXISTS idx_event_participants_vote_token ON event_participants(vote_token);
CREATE INDEX IF NOT EXISTS idx_event_participants_email ON event_participants(email);

-- Votes indexes
CREATE INDEX IF NOT EXISTS idx_event_votes_event_id ON event_votes(event_id);
CREATE INDEX IF NOT EXISTS idx_event_votes_participant_id ON event_votes(participant_id);
CREATE INDEX IF NOT EXISTS idx_event_votes_event_artist_id ON event_votes(event_artist_id);
CREATE INDEX IF NOT EXISTS idx_event_votes_created_at ON event_votes(created_at);

-- Follow-ups indexes
CREATE INDEX IF NOT EXISTS idx_event_follow_ups_event_id ON event_follow_ups(event_id);
CREATE INDEX IF NOT EXISTS idx_event_follow_ups_participant_id ON event_follow_ups(participant_id);
CREATE INDEX IF NOT EXISTS idx_event_follow_ups_type ON event_follow_ups(follow_up_type);

-- ===============================================
-- RLS POLICIES
-- ===============================================

-- Enable RLS
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_follow_ups ENABLE ROW LEVEL SECURITY;

-- Events policies
CREATE POLICY "Event hosts can manage their events" ON events
  FOR ALL USING (host_user_id = auth.uid());

CREATE POLICY "Published events are publicly viewable" ON events
  FOR SELECT USING (status IN ('published', 'live', 'completed'));

-- Event artists policies
CREATE POLICY "Event hosts can manage event artists" ON event_artists
  FOR ALL USING (
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND host_user_id = auth.uid())
  );

CREATE POLICY "Artists can view and update their own event registrations" ON event_artists
  FOR ALL USING (
    EXISTS(SELECT 1 FROM artist_profiles WHERE id = artist_profile_id AND user_id = auth.uid())
  );

CREATE POLICY "Public can view confirmed event artists" ON event_artists
  FOR SELECT USING (
    registration_status = 'confirmed' AND
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND status IN ('published', 'live', 'completed'))
  );

-- Event participants policies (anonymous voting support)
CREATE POLICY "Anyone can create event participants" ON event_participants
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Participants can view their own data by token" ON event_participants
  FOR SELECT USING (true); -- Token-based access handled in application layer

CREATE POLICY "Event hosts can view all participants" ON event_participants
  FOR SELECT USING (
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND host_user_id = auth.uid())
  );

-- Votes policies
CREATE POLICY "Anyone can cast votes" ON event_votes
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Event hosts can view all votes" ON event_votes
  FOR SELECT USING (
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND host_user_id = auth.uid())
  );

-- Follow-ups policies
CREATE POLICY "Event hosts can manage follow-ups" ON event_follow_ups
  FOR ALL USING (
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND host_user_id = auth.uid())
  );

-- ===============================================
-- HELPER FUNCTIONS
-- ===============================================

-- Function to generate shareable codes
CREATE OR REPLACE FUNCTION generate_event_shareable_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  code TEXT;
  exists_check INTEGER;
BEGIN
  LOOP
    -- Generate 8-character alphanumeric code
    code := UPPER(substring(encode(gen_random_bytes(6), 'base64') from 1 for 8));
    code := replace(replace(replace(code, '+', ''), '/', ''), '=', '');

    -- Ensure it's exactly 8 characters
    IF LENGTH(code) < 8 THEN
      code := code || UPPER(substring(encode(gen_random_bytes(2), 'base64') from 1 for 8 - LENGTH(code)));
    END IF;
    code := substring(code from 1 for 8);

    -- Check if code already exists
    SELECT COUNT(*) INTO exists_check FROM events WHERE shareable_code = code;

    -- Exit loop if code is unique
    IF exists_check = 0 THEN
      EXIT;
    END IF;
  END LOOP;

  RETURN code;
END;
$$;

-- Function to update vote counts
CREATE OR REPLACE FUNCTION update_event_artist_vote_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE event_artists
    SET vote_count = vote_count + NEW.vote_weight,
        updated_at = now()
    WHERE id = NEW.event_artist_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE event_artists
    SET vote_count = GREATEST(0, vote_count - OLD.vote_weight),
        updated_at = now()
    WHERE id = OLD.event_artist_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

-- Trigger to automatically update vote counts
DROP TRIGGER IF EXISTS trigger_update_event_artist_vote_count ON event_votes;
CREATE TRIGGER trigger_update_event_artist_vote_count
  AFTER INSERT OR DELETE ON event_votes
  FOR EACH ROW EXECUTE FUNCTION update_event_artist_vote_count();

-- ===============================================
-- SAMPLE DATA FUNCTIONS (FOR DEVELOPMENT)
-- ===============================================

-- Function to create sample event (for testing)
CREATE OR REPLACE FUNCTION create_sample_concierto_event(host_id UUID)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
  event_id UUID;
BEGIN
  INSERT INTO events (
    title,
    description,
    start_date,
    end_date,
    voting_opens_at,
    voting_closes_at,
    host_user_id,
    shareable_code,
    status
  ) VALUES (
    'Sample Concierto Event',
    'A test event for the Concierto voting system',
    now() + interval '1 day',
    now() + interval '3 days',
    now() + interval '1 day',
    now() + interval '2 days',
    host_id,
    generate_event_shareable_code(),
    'draft'
  ) RETURNING id INTO event_id;

  RETURN event_id;
END;
$$;