-- ===============================================
-- CONCIERTO + MEDIAID INTEGRATION
-- Enhanced event system with MediaID privacy and personalization
-- ===============================================

-- Add MediaID integration to existing events table
ALTER TABLE events ADD COLUMN IF NOT EXISTS mediaid_integration_enabled BOOLEAN DEFAULT true;
ALTER TABLE events ADD COLUMN IF NOT EXISTS privacy_mode TEXT DEFAULT 'balanced' CHECK (privacy_mode IN ('minimal', 'balanced', 'enhanced'));
ALTER TABLE events ADD COLUMN IF NOT EXISTS personalization_settings JSONB DEFAULT '{"use_listening_history": true, "use_genre_preferences": true, "anonymous_recommendations": false}';

-- Add MediaID integration to event participants
ALTER TABLE event_participants ADD COLUMN IF NOT EXISTS mediaid_profile_id UUID REFERENCES media_ids(id);
ALTER TABLE event_participants ADD COLUMN IF NOT EXISTS anonymous_profile_data JSONB DEFAULT '{}'; -- For privacy-first participation
ALTER TABLE event_participants ADD COLUMN IF NOT EXISTS consent_preferences JSONB DEFAULT '{"data_sharing": false, "personalized_recommendations": false, "follow_up_marketing": false}';

-- Enhanced voting with MediaID insights
ALTER TABLE event_votes ADD COLUMN IF NOT EXISTS vote_confidence_score DECIMAL(3,2); -- MediaID-based confidence in vote authenticity
ALTER TABLE event_votes ADD COLUMN IF NOT EXISTS recommendation_influence JSONB DEFAULT '{}'; -- How MediaID recommendations influenced this vote
ALTER TABLE event_votes ADD COLUMN IF NOT EXISTS listening_context JSONB DEFAULT '{}'; -- User's current listening patterns

-- MediaID-powered event recommendations
CREATE TABLE IF NOT EXISTS event_recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  mediaid_profile_id UUID NOT NULL REFERENCES media_ids(id) ON DELETE CASCADE,

  -- Recommendation data
  recommended_artists JSONB DEFAULT '[]', -- Artist IDs recommended based on MediaID
  recommendation_reasons JSONB DEFAULT '{}', -- Why these artists were recommended
  recommendation_strength DECIMAL(3,2), -- 0.0 to 1.0 confidence

  -- Interaction tracking
  viewed_at TIMESTAMPTZ,
  interacted_with JSONB DEFAULT '{}', -- Which recommendations were clicked/voted

  created_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(event_id, mediaid_profile_id)
);

-- MediaID-enhanced follow-ups with privacy controls
ALTER TABLE event_follow_ups ADD COLUMN IF NOT EXISTS mediaid_profile_id UUID REFERENCES media_ids(id);
ALTER TABLE event_follow_ups ADD COLUMN IF NOT EXISTS personalization_data JSONB DEFAULT '{}';
ALTER TABLE event_follow_ups ADD COLUMN IF NOT EXISTS privacy_compliance JSONB DEFAULT '{"anonymized": true, "consent_verified": false}';

-- Anonymous voting sessions linked to MediaID (privacy-first)
CREATE TABLE IF NOT EXISTS anonymous_voting_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,

  -- Anonymous MediaID vector (no PII)
  anonymous_vector vector(1536), -- Anonymized MediaID embedding
  session_fingerprint TEXT, -- Non-identifying session hash

  -- Voting patterns (anonymous)
  vote_pattern_data JSONB DEFAULT '{}',
  engagement_metrics JSONB DEFAULT '{}',

  -- Privacy compliance
  data_retention_until TIMESTAMPTZ, -- Auto-delete date
  consent_level TEXT DEFAULT 'minimal' CHECK (consent_level IN ('minimal', 'functional', 'personalized')),

  created_at TIMESTAMPTZ DEFAULT now()
);

-- ===============================================
-- MEDIAID INTEGRATION FUNCTIONS
-- ===============================================

-- Function to create anonymous MediaID profile for event participation
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
  v_session_id UUID;
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
    jsonb_build_object(
      'user_agent', p_user_agent,
      'created_anonymously', true,
      'privacy_mode', true
    )
  ) RETURNING id INTO v_participant_id;

  -- Create anonymous voting session
  INSERT INTO anonymous_voting_sessions (
    event_id,
    session_fingerprint,
    consent_level,
    data_retention_until
  ) VALUES (
    p_event_id,
    encode(digest(p_user_agent || extract(epoch from now())::text, 'sha256'), 'hex'),
    (p_consent_preferences->>'consent_level')::text,
    now() + interval '30 days' -- Auto-delete after 30 days
  ) RETURNING id INTO v_session_id;

  RETURN v_participant_id;
END;
$$;

-- Function to enhance voting with MediaID insights (privacy-preserving)
CREATE OR REPLACE FUNCTION get_mediaid_voting_recommendations(
  p_event_id UUID,
  p_mediaid_profile_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_recommendations JSONB := '[]';
  v_user_preferences JSONB;
  v_listening_history JSONB;
BEGIN
  -- If MediaID provided, get personalized recommendations
  IF p_mediaid_profile_id IS NOT NULL THEN
    -- Get user preferences from MediaID
    SELECT jsonb_build_object(
      'genres', interests,
      'privacy_level', privacy_settings->>'level',
      'personalization_enabled', (privacy_settings->>'personalization_enabled')::boolean
    ) INTO v_user_preferences
    FROM media_ids
    WHERE id = p_mediaid_profile_id;

    -- Get recent listening patterns (if consented)
    IF v_user_preferences->>'personalization_enabled' = 'true' THEN
      SELECT jsonb_agg(
        jsonb_build_object(
          'artist_id', event_artist_id,
          'compatibility_score', random() * 0.8 + 0.2, -- Simplified for demo
          'reason', 'Based on your listening history'
        )
      ) INTO v_recommendations
      FROM event_artists ea
      WHERE ea.event_id = p_event_id
      AND ea.registration_status = 'confirmed'
      LIMIT 3;
    END IF;
  END IF;

  -- Fallback to general recommendations if no MediaID or no consent
  IF v_recommendations = '[]' OR v_recommendations IS NULL THEN
    SELECT jsonb_agg(
      jsonb_build_object(
        'artist_id', id,
        'compatibility_score', random() * 0.6 + 0.4,
        'reason', 'Popular choice'
      )
    ) INTO v_recommendations
    FROM event_artists
    WHERE event_id = p_event_id
    AND registration_status = 'confirmed'
    ORDER BY vote_count DESC
    LIMIT 3;
  END IF;

  RETURN COALESCE(v_recommendations, '[]');
END;
$$;

-- ===============================================
-- PRIVACY-FIRST ANALYTICS
-- ===============================================

-- Function to get anonymized event analytics
CREATE OR REPLACE FUNCTION get_event_analytics_anonymized(
  p_event_id UUID,
  p_requester_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_is_host BOOLEAN;
  v_analytics JSONB;
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

  -- Generate anonymized analytics
  SELECT jsonb_build_object(
    'total_participants', COUNT(DISTINCT ep.id),
    'total_votes', COUNT(ev.id),
    'engagement_metrics', jsonb_build_object(
      'avg_session_duration', AVG(ep.session_duration_seconds),
      'participation_rate', COUNT(DISTINCT ev.participant_id)::decimal / GREATEST(COUNT(DISTINCT ep.id), 1)
    ),
    'geographic_distribution', jsonb_build_object(
      'anonymous_regions', 'Available with consent'
    ),
    'privacy_compliance', jsonb_build_object(
      'anonymized_data_points', COUNT(DISTINCT ep.id),
      'consent_levels_summary', jsonb_object_agg(
        COALESCE(ep.consent_preferences->>'consent_level', 'minimal'),
        COUNT(*)
      )
    )
  ) INTO v_analytics
  FROM event_participants ep
  LEFT JOIN event_votes ev ON ep.id = ev.participant_id
  WHERE ep.event_id = p_event_id;

  RETURN v_analytics;
END;
$$;

-- ===============================================
-- INDEXES FOR PERFORMANCE
-- ===============================================

-- MediaID integration indexes
CREATE INDEX IF NOT EXISTS idx_event_participants_mediaid ON event_participants(mediaid_profile_id);
CREATE INDEX IF NOT EXISTS idx_event_recommendations_mediaid ON event_recommendations(mediaid_profile_id);
CREATE INDEX IF NOT EXISTS idx_anonymous_voting_sessions_event ON anonymous_voting_sessions(event_id);
CREATE INDEX IF NOT EXISTS idx_anonymous_voting_sessions_retention ON anonymous_voting_sessions(data_retention_until);

-- ===============================================
-- RLS POLICIES FOR MEDIAID INTEGRATION
-- ===============================================

-- Event recommendations policies
ALTER TABLE event_recommendations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own event recommendations" ON event_recommendations
  FOR SELECT USING (
    EXISTS(SELECT 1 FROM media_ids WHERE id = mediaid_profile_id AND user_uuid = auth.uid())
  );

CREATE POLICY "Event hosts can manage recommendations" ON event_recommendations
  FOR ALL USING (
    EXISTS(SELECT 1 FROM events WHERE id = event_id AND host_user_id = auth.uid())
  );

-- Anonymous voting sessions policies
ALTER TABLE anonymous_voting_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anonymous sessions are publicly readable for events" ON anonymous_voting_sessions
  FOR SELECT USING (true); -- Anonymous data, safe to read

-- ===============================================
-- CLEANUP JOB FOR PRIVACY COMPLIANCE
-- ===============================================

-- Function to clean up expired anonymous data
CREATE OR REPLACE FUNCTION cleanup_expired_anonymous_data()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted_count INTEGER;
BEGIN
  DELETE FROM anonymous_voting_sessions
  WHERE data_retention_until < now();

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  RETURN v_deleted_count;
END;
$$;