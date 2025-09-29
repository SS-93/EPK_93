-- CRM Artist Workflow - Treat Artists as Leads/Prospects
-- Artists don't need to be authenticated users for events
-- Host manages all artist data like a CRM system

-- ===============================================
-- 1. CREATE EVENT ARTIST PROSPECTS TABLE
-- ===============================================

CREATE TABLE IF NOT EXISTS event_artist_prospects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,

  -- CRM Lead Data
  artist_name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  instagram_handle TEXT,
  spotify_url TEXT,
  apple_music_url TEXT,

  -- Event-specific data
  bio TEXT,
  stage_name TEXT, -- Might be different from artist_name
  performance_notes TEXT,

  -- CRM Status
  contact_status TEXT DEFAULT 'invited' CHECK (contact_status IN (
    'invited', 'contacted', 'confirmed', 'declined', 'no_response', 'withdrawn'
  )),

  -- Registration & tokens
  registration_token TEXT UNIQUE,
  registration_completed_at TIMESTAMPTZ,

  -- Host CRM notes
  host_notes TEXT,
  tags TEXT[], -- ['local', 'hip-hop', 'needs-followup']
  priority INTEGER DEFAULT 5 CHECK (priority BETWEEN 1 AND 10),

  -- Voting data
  vote_count INTEGER DEFAULT 0,
  final_placement INTEGER,

  -- Contact tracking
  last_contacted_at TIMESTAMPTZ,
  contact_method TEXT, -- 'email', 'phone', 'instagram', 'in_person'

  -- Future migration to full user
  migrated_to_user_id UUID REFERENCES auth.users(id),
  migration_completed_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ===============================================
-- 2. UPDATE RLS POLICIES FOR CRM WORKFLOW
-- ===============================================

-- Enable RLS
ALTER TABLE event_artist_prospects ENABLE ROW LEVEL SECURITY;

-- Host can manage all their event artist prospects
DROP POLICY IF EXISTS "Event hosts can manage artist prospects" ON event_artist_prospects;
CREATE POLICY "Event hosts can manage artist prospects" ON event_artist_prospects
  FOR ALL USING (
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND host_user_id = auth.uid())
  );

-- Public can view confirmed artists for published events
DROP POLICY IF EXISTS "Public can view confirmed event artists" ON event_artist_prospects;
CREATE POLICY "Public can view confirmed event artists" ON event_artist_prospects
  FOR SELECT USING (
    contact_status = 'confirmed' AND
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND status IN ('published', 'live', 'completed'))
  );

-- Artists can register via token (no auth required)
DROP POLICY IF EXISTS "Anyone can register with valid token" ON event_artist_prospects;
CREATE POLICY "Anyone can register with valid token" ON event_artist_prospects
  FOR UPDATE WITH CHECK (registration_token IS NOT NULL);

-- ===============================================
-- 3. MODIFY EXISTING ARTIST_PROFILES FOR COMPATIBILITY
-- ===============================================

-- Allow hosts to create artist profiles for their events (bypass RLS for events)
DROP POLICY IF EXISTS "Event hosts can create artist profiles" ON artist_profiles;
CREATE POLICY "Event hosts can create artist profiles" ON artist_profiles
  FOR INSERT WITH CHECK (
    -- Allow if user is creating for their own events
    EXISTS(SELECT 1 FROM events WHERE host_user_id = auth.uid())
  );

-- Allow public read for published content
DROP POLICY IF EXISTS "Public can view published artist profiles" ON artist_profiles;
CREATE POLICY "Public can view published artist profiles" ON artist_profiles
  FOR SELECT USING (true); -- Make all artist profiles publicly readable

-- ===============================================
-- 4. CREATE CRM HELPER FUNCTIONS
-- ===============================================

-- Function to add artist prospect to event
CREATE OR REPLACE FUNCTION add_artist_prospect_to_event(
  p_event_id UUID,
  p_artist_name TEXT,
  p_email TEXT DEFAULT NULL,
  p_instagram_handle TEXT DEFAULT NULL,
  p_bio TEXT DEFAULT NULL,
  p_host_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_prospect_id UUID;
  v_registration_token TEXT;
BEGIN
  -- Generate registration token
  v_registration_token := 'reg_' || encode(gen_random_bytes(32), 'base64url');

  -- Create artist prospect
  INSERT INTO event_artist_prospects (
    event_id,
    artist_name,
    email,
    instagram_handle,
    bio,
    host_notes,
    registration_token,
    contact_status,
    created_at
  ) VALUES (
    p_event_id,
    p_artist_name,
    p_email,
    p_instagram_handle,
    p_bio,
    p_host_notes,
    v_registration_token,
    'invited',
    now()
  ) RETURNING id INTO v_prospect_id;

  RETURN v_prospect_id;
END;
$$;

-- Function to update artist prospect contact status
CREATE OR REPLACE FUNCTION update_artist_prospect_status(
  p_prospect_id UUID,
  p_status TEXT,
  p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE event_artist_prospects
  SET
    contact_status = p_status,
    host_notes = COALESCE(p_notes, host_notes),
    last_contacted_at = CASE
      WHEN p_status IN ('contacted', 'confirmed') THEN now()
      ELSE last_contacted_at
    END,
    updated_at = now()
  WHERE id = p_prospect_id;

  RETURN FOUND;
END;
$$;

-- Function to get event CRM dashboard data
CREATE OR REPLACE FUNCTION get_event_crm_summary(p_event_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_summary JSON;
BEGIN
  SELECT json_build_object(
    'total_prospects', COUNT(*),
    'confirmed', COUNT(*) FILTER (WHERE contact_status = 'confirmed'),
    'pending', COUNT(*) FILTER (WHERE contact_status IN ('invited', 'contacted')),
    'declined', COUNT(*) FILTER (WHERE contact_status = 'declined'),
    'no_response', COUNT(*) FILTER (WHERE contact_status = 'no_response'),
    'total_votes', SUM(vote_count),
    'top_artists', json_agg(
      json_build_object(
        'name', artist_name,
        'votes', vote_count,
        'status', contact_status
      ) ORDER BY vote_count DESC
    ) FILTER (WHERE vote_count > 0)
  ) INTO v_summary
  FROM event_artist_prospects
  WHERE event_id = p_event_id;

  RETURN v_summary;
END;
$$;

-- ===============================================
-- 5. CREATE INDEXES FOR CRM PERFORMANCE
-- ===============================================

CREATE INDEX IF NOT EXISTS idx_event_artist_prospects_event ON event_artist_prospects(event_id);
CREATE INDEX IF NOT EXISTS idx_event_artist_prospects_status ON event_artist_prospects(contact_status);
CREATE INDEX IF NOT EXISTS idx_event_artist_prospects_token ON event_artist_prospects(registration_token);
CREATE INDEX IF NOT EXISTS idx_event_artist_prospects_email ON event_artist_prospects(email);
CREATE INDEX IF NOT EXISTS idx_event_artist_prospects_votes ON event_artist_prospects(vote_count DESC);
CREATE INDEX IF NOT EXISTS idx_event_artist_prospects_priority ON event_artist_prospects(priority DESC);

-- ===============================================
-- 6. CREATE TRIGGERS FOR CRM AUTOMATION
-- ===============================================

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_event_artist_prospects_updated_at ON event_artist_prospects;
CREATE TRIGGER update_event_artist_prospects_updated_at
  BEFORE UPDATE ON event_artist_prospects
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-generate registration tokens
CREATE OR REPLACE FUNCTION generate_registration_token()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.registration_token IS NULL THEN
    NEW.registration_token := 'reg_' || encode(gen_random_bytes(32), 'base64url');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS auto_generate_registration_token ON event_artist_prospects;
CREATE TRIGGER auto_generate_registration_token
  BEFORE INSERT ON event_artist_prospects
  FOR EACH ROW EXECUTE FUNCTION generate_registration_token();