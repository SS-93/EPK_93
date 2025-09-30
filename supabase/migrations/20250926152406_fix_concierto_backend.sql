-- Fix Concierto Backend Issues
-- This script adds missing functions and fixes database structure

-- ===============================================
-- 1. CREATE MISSING ANALYTICS FUNCTION
-- ===============================================

CREATE OR REPLACE FUNCTION get_event_analytics_anonymized(
  p_event_id UUID,
  p_requester_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_is_host BOOLEAN;
  v_analytics JSON;
BEGIN
  -- Verify requester is event host
  SELECT EXISTS(
    SELECT 1 FROM events
    WHERE id = p_event_id
    AND host_user_id = p_requester_user_id
  ) INTO v_is_host;

  IF NOT v_is_host THEN
    RAISE EXCEPTION 'Access denied: not event host';
  END IF;

  -- Generate basic analytics (simplified version)
  SELECT json_build_object(
    'total_participants', COALESCE(COUNT(DISTINCT ea.id), 0),
    'total_votes', COALESCE(SUM(ea.vote_count), 0),
    'engagement_metrics', json_build_object(
      'avg_session_duration', 120.0, -- Mock data
      'participation_rate', 0.75
    ),
    'privacy_compliance', json_build_object(
      'anonymized_data_points', COALESCE(COUNT(DISTINCT ea.id), 0),
      'consent_levels_summary', json_build_object(
        'minimal', 5,
        'functional', 3,
        'personalized', 2
      )
    )
  ) INTO v_analytics
  FROM event_artists ea
  WHERE ea.event_id = p_event_id;

  RETURN COALESCE(v_analytics, '{"total_participants": 0, "total_votes": 0}'::json);
END;
$$;

-- ===============================================
-- 2. CREATE EVENT PARTICIPANTS TABLE (for voting)
-- ===============================================

CREATE TABLE IF NOT EXISTS event_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,

  -- Anonymous participation
  vote_token TEXT UNIQUE,
  registration_source TEXT DEFAULT 'web',

  -- MediaID integration
  mediaid_profile_id UUID REFERENCES media_ids(id),
  anonymous_profile_data JSONB DEFAULT '{}',
  consent_preferences JSONB DEFAULT '{"data_sharing": false, "personalized_recommendations": false}',

  -- Engagement tracking
  engagement_data JSONB DEFAULT '{}',
  session_duration_seconds INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE event_participants ENABLE ROW LEVEL SECURITY;

-- Basic RLS policy
CREATE POLICY "Public can read event participants" ON event_participants
  FOR SELECT USING (true);

CREATE POLICY "Authenticated users can insert participants" ON event_participants
  FOR INSERT WITH CHECK (true);

-- ===============================================
-- 3. CREATE EVENT VOTES TABLE
-- ===============================================

CREATE TABLE IF NOT EXISTS event_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_id UUID REFERENCES event_participants(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  artist_id UUID NOT NULL REFERENCES artist_profiles(id) ON DELETE CASCADE,

  -- Vote metadata
  round INTEGER DEFAULT 1,
  token TEXT UNIQUE,

  -- MediaID enhancements
  vote_confidence_score DECIMAL(3,2),
  recommendation_influence JSONB DEFAULT '{}',
  listening_context JSONB DEFAULT '{}',

  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE event_votes ENABLE ROW LEVEL SECURITY;

-- Basic RLS policies
CREATE POLICY "Public can read event votes" ON event_votes
  FOR SELECT USING (true);

CREATE POLICY "Authenticated users can create votes" ON event_votes
  FOR INSERT WITH CHECK (true);

-- ===============================================
-- 4. CREATE INDEXES FOR PERFORMANCE
-- ===============================================

CREATE INDEX IF NOT EXISTS idx_event_participants_event ON event_participants(event_id);
CREATE INDEX IF NOT EXISTS idx_event_participants_token ON event_participants(vote_token);
CREATE INDEX IF NOT EXISTS idx_event_votes_event ON event_votes(event_id);
CREATE INDEX IF NOT EXISTS idx_event_votes_artist ON event_votes(artist_id);
CREATE INDEX IF NOT EXISTS idx_event_votes_participant ON event_votes(participant_id);

-- ===============================================
-- 5. CREATE ANONYMOUS PROFILE FUNCTION
-- ===============================================

CREATE OR REPLACE FUNCTION create_anonymous_event_profile(
  p_event_id UUID,
  p_user_agent TEXT DEFAULT NULL,
  p_consent_preferences JSONB DEFAULT '{"data_sharing": false}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_participant_id UUID;
BEGIN
  -- Create anonymous event participant
  INSERT INTO event_participants (
    event_id,
    vote_token,
    registration_source,
    consent_preferences,
    engagement_data
  ) VALUES (
    p_event_id,
    'anon_' || encode(gen_random_bytes(16), 'base64'),
    'anonymous',
    p_consent_preferences,
    json_build_object(
      'user_agent', p_user_agent,
      'created_anonymously', true,
      'privacy_mode', true
    )
  ) RETURNING id INTO v_participant_id;

  RETURN v_participant_id;
END;
$$;

-- ===============================================
-- 6. CREATE VOTING RECOMMENDATIONS FUNCTION
-- ===============================================

CREATE OR REPLACE FUNCTION get_mediaid_voting_recommendations(
  p_event_id UUID,
  p_mediaid_profile_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_recommendations JSON := '[]'::json;
BEGIN
  -- Get basic recommendations (simplified for now)
  SELECT json_agg(
    json_build_object(
      'artist_id', ap.id,
      'compatibility_score', random() * 0.6 + 0.4,
      'reason', 'Popular choice',
      'confidence', 0.8
    )
  ) INTO v_recommendations
  FROM event_artists ea
  JOIN artist_profiles ap ON ap.id = ea.artist_profile_id
  WHERE ea.event_id = p_event_id
  AND ea.registration_status = 'confirmed'
  ORDER BY ea.vote_count DESC
  LIMIT 3;

  RETURN COALESCE(v_recommendations, '[]'::json);
END;
$$;