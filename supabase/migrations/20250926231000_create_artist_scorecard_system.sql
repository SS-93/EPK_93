-- Create Artist Scorecard Evaluation System
-- Enables detailed performance metrics, AI analytics, and digital memorabilia

-- Artist Scorecard Evaluations table
CREATE TABLE IF NOT EXISTS artist_scorecard_evaluations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  artist_id UUID NOT NULL, -- References event_artist_prospects(id)

  -- Evaluator information
  evaluator_id UUID, -- Can be null for anonymous evaluations
  evaluator_name TEXT NOT NULL,
  evaluator_type VARCHAR(20) CHECK (evaluator_type IN ('audience', 'artist', 'host', 'judge')) NOT NULL,

  -- Scorecard metrics (all scored 1-5)
  metrics JSONB NOT NULL DEFAULT '{}',

  -- Additional feedback
  written_feedback TEXT,
  tags TEXT[] DEFAULT '{}',

  -- Metadata
  is_public BOOLEAN DEFAULT true,
  is_verified BOOLEAN DEFAULT false, -- For verified industry professionals

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  -- Ensure one evaluation per evaluator per artist per event
  UNIQUE(event_id, artist_id, evaluator_id)
);

-- AI-generated artist insights table
CREATE TABLE IF NOT EXISTS artist_ai_insights (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  artist_id UUID NOT NULL,

  -- AI Analysis Data
  aggregate_scores JSONB NOT NULL DEFAULT '{}',
  strengths TEXT[] DEFAULT '{}',
  improvement_areas TEXT[] DEFAULT '{}',
  sentiment_analysis JSONB DEFAULT '{}',
  performance_trends JSONB DEFAULT '{}',
  audience_demographics JSONB DEFAULT '{}',

  -- AI-generated content
  ai_summary TEXT,
  ai_recommendations TEXT,
  key_insights TEXT[],

  -- Memorabilia generation data
  highlight_moments JSONB DEFAULT '{}',
  quotable_feedback TEXT[],
  visual_elements JSONB DEFAULT '{}',

  -- Metadata
  total_evaluations INTEGER DEFAULT 0,
  confidence_score DECIMAL(3,2), -- 0.00 to 1.00
  generated_at TIMESTAMPTZ DEFAULT now(),
  last_updated TIMESTAMPTZ DEFAULT now()
);

-- Digital memorabilia table
CREATE TABLE IF NOT EXISTS digital_memorabilia (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id UUID NOT NULL,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,

  -- Memorabilia content
  title TEXT NOT NULL,
  description TEXT,
  memorabilia_type VARCHAR(50) CHECK (memorabilia_type IN ('performance_report', 'audience_highlights', 'achievement_badge', 'growth_chart', 'fan_testimonials')) NOT NULL,

  -- Visual and content data
  content_data JSONB NOT NULL DEFAULT '{}',
  visual_assets JSONB DEFAULT '{}', -- URLs to generated images, charts, etc.

  -- Sharing and access
  is_public BOOLEAN DEFAULT true,
  shareable_url TEXT UNIQUE,
  view_count INTEGER DEFAULT 0,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ, -- Optional expiration

  -- Search and discovery
  tags TEXT[] DEFAULT '{}',
  search_keywords TEXT[]
);

-- Evaluation analytics aggregation table (for performance)
CREATE TABLE IF NOT EXISTS evaluation_analytics_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id UUID NOT NULL,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,

  -- Cached aggregate data
  total_evaluations INTEGER DEFAULT 0,
  average_overall_rating DECIMAL(3,2),
  average_metrics JSONB DEFAULT '{}',

  -- Distribution data
  rating_distribution JSONB DEFAULT '{}',
  evaluator_type_breakdown JSONB DEFAULT '{}',
  most_common_tags TEXT[],

  -- Performance indicators
  percentile_rank INTEGER, -- 0-100 compared to other artists in event
  improvement_score DECIMAL(3,2), -- Change from previous events

  -- Cache metadata
  calculated_at TIMESTAMPTZ DEFAULT now(),
  is_stale BOOLEAN DEFAULT false
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_scorecard_evaluations_artist_event ON artist_scorecard_evaluations(artist_id, event_id);
CREATE INDEX IF NOT EXISTS idx_scorecard_evaluations_evaluator ON artist_scorecard_evaluations(evaluator_id, evaluator_type);
CREATE INDEX IF NOT EXISTS idx_scorecard_evaluations_created_at ON artist_scorecard_evaluations(created_at);
CREATE INDEX IF NOT EXISTS idx_ai_insights_artist_event ON artist_ai_insights(artist_id, event_id);
CREATE INDEX IF NOT EXISTS idx_digital_memorabilia_artist ON digital_memorabilia(artist_id, event_id);
CREATE INDEX IF NOT EXISTS idx_digital_memorabilia_public ON digital_memorabilia(is_public, created_at);
CREATE INDEX IF NOT EXISTS idx_analytics_cache_artist_event ON evaluation_analytics_cache(artist_id, event_id);

-- RLS policies
ALTER TABLE artist_scorecard_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE artist_ai_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE digital_memorabilia ENABLE ROW LEVEL SECURITY;
ALTER TABLE evaluation_analytics_cache ENABLE ROW LEVEL SECURITY;

-- Scorecard evaluation policies
CREATE POLICY "Anyone can view public evaluations"
  ON artist_scorecard_evaluations FOR SELECT
  USING (is_public = true);

CREATE POLICY "Users can create evaluations"
  ON artist_scorecard_evaluations FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Users can update their own evaluations"
  ON artist_scorecard_evaluations FOR UPDATE
  USING (evaluator_id = auth.uid());

-- AI insights policies
CREATE POLICY "Anyone can view AI insights"
  ON artist_ai_insights FOR SELECT
  USING (true);

CREATE POLICY "System can manage AI insights"
  ON artist_ai_insights FOR ALL
  USING (true);

-- Digital memorabilia policies
CREATE POLICY "Anyone can view public memorabilia"
  ON digital_memorabilia FOR SELECT
  USING (is_public = true);

CREATE POLICY "System can manage memorabilia"
  ON digital_memorabilia FOR ALL
  USING (true);

-- Analytics cache policies
CREATE POLICY "Anyone can view analytics cache"
  ON evaluation_analytics_cache FOR SELECT
  USING (true);

-- Functions for scorecard system

-- Function to calculate aggregate artist scores
CREATE OR REPLACE FUNCTION get_artist_aggregate_scorecard(
  p_artist_id UUID,
  p_event_id UUID
)
RETURNS TABLE (
  artist_id UUID,
  event_id UUID,
  total_evaluations BIGINT,
  average_overall_rating NUMERIC,
  average_metrics JSONB,
  rating_distribution JSONB,
  most_common_tags TEXT[],
  top_strengths TEXT[],
  improvement_areas TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH evaluation_stats AS (
    SELECT
      COUNT(*) as eval_count,
      AVG((metrics->>'overall_rating')::numeric) as avg_rating,
      jsonb_object_agg(metric_key, AVG(metric_value::numeric)) as avg_metrics_obj
    FROM artist_scorecard_evaluations e,
    LATERAL jsonb_each_text(e.metrics) as metric(metric_key, metric_value)
    WHERE e.artist_id = p_artist_id
    AND e.event_id = p_event_id
    AND metric_value ~ '^[0-9]+\.?[0-9]*$'
  ),
  tag_stats AS (
    SELECT array_agg(tag) as common_tags
    FROM (
      SELECT unnest(tags) as tag, COUNT(*) as tag_count
      FROM artist_scorecard_evaluations
      WHERE artist_id = p_artist_id AND event_id = p_event_id
      GROUP BY tag
      ORDER BY tag_count DESC
      LIMIT 10
    ) t
  )
  SELECT
    p_artist_id,
    p_event_id,
    COALESCE(eval_count, 0),
    COALESCE(avg_rating, 0),
    COALESCE(avg_metrics_obj, '{}'::jsonb),
    '{}'::jsonb, -- Rating distribution calculation would go here
    COALESCE(common_tags, '{}'),
    '{}', -- Top strengths from AI analysis
    '{}' -- Improvement areas from AI analysis
  FROM evaluation_stats, tag_stats;
END;
$$;

-- Function to generate AI insights (placeholder for actual AI integration)
CREATE OR REPLACE FUNCTION generate_ai_artist_insights(
  p_artist_id UUID,
  p_event_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_insight_id UUID;
  v_eval_count INTEGER;
  v_avg_rating NUMERIC;
BEGIN
  -- Get basic stats
  SELECT COUNT(*), AVG((metrics->>'overall_rating')::numeric)
  INTO v_eval_count, v_avg_rating
  FROM artist_scorecard_evaluations
  WHERE artist_id = p_artist_id AND event_id = p_event_id;

  -- Generate or update AI insights
  INSERT INTO artist_ai_insights (
    artist_id,
    event_id,
    aggregate_scores,
    ai_summary,
    total_evaluations,
    confidence_score
  ) VALUES (
    p_artist_id,
    p_event_id,
    jsonb_build_object('overall_rating', v_avg_rating),
    'AI analysis based on ' || v_eval_count || ' evaluations. Detailed insights coming soon.',
    v_eval_count,
    CASE
      WHEN v_eval_count >= 10 THEN 0.9
      WHEN v_eval_count >= 5 THEN 0.7
      ELSE 0.5
    END
  )
  ON CONFLICT (artist_id, event_id)
  DO UPDATE SET
    total_evaluations = v_eval_count,
    aggregate_scores = jsonb_build_object('overall_rating', v_avg_rating),
    confidence_score = CASE
      WHEN v_eval_count >= 10 THEN 0.9
      WHEN v_eval_count >= 5 THEN 0.7
      ELSE 0.5
    END,
    last_updated = now()
  RETURNING id INTO v_insight_id;

  -- Trigger memorabilia generation
  PERFORM generate_digital_memorabilia(p_artist_id, p_event_id);

  RETURN v_insight_id;
END;
$$;

-- Function to generate digital memorabilia
CREATE OR REPLACE FUNCTION generate_digital_memorabilia(
  p_artist_id UUID,
  p_event_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_memorabilia_id UUID;
  v_event_title TEXT;
  v_artist_name TEXT;
  v_shareable_url TEXT;
BEGIN
  -- Get event and artist info
  SELECT title INTO v_event_title FROM events WHERE id = p_event_id;
  SELECT artist_name INTO v_artist_name FROM event_artist_prospects WHERE id = p_artist_id;

  -- Generate unique shareable URL
  v_shareable_url := 'memorabilia_' || encode(gen_random_bytes(16), 'base64');
  v_shareable_url := replace(replace(replace(v_shareable_url, '+', 'X'), '/', 'Y'), '=', 'Z');

  -- Create performance report memorabilia
  INSERT INTO digital_memorabilia (
    artist_id,
    event_id,
    title,
    description,
    memorabilia_type,
    content_data,
    shareable_url,
    tags
  ) VALUES (
    p_artist_id,
    p_event_id,
    v_artist_name || ' - ' || v_event_title || ' Performance Report',
    'Comprehensive evaluation report with audience feedback and insights',
    'performance_report',
    jsonb_build_object(
      'event_name', v_event_title,
      'artist_name', v_artist_name,
      'generated_at', now(),
      'type', 'ai_generated_report'
    ),
    v_shareable_url,
    ARRAY['performance', 'evaluation', 'report', v_event_title]
  )
  ON CONFLICT (artist_id, event_id)
  DO UPDATE SET
    content_data = jsonb_build_object(
      'event_name', v_event_title,
      'artist_name', v_artist_name,
      'updated_at', now(),
      'type', 'ai_generated_report'
    )
  RETURNING id INTO v_memorabilia_id;

  RETURN v_memorabilia_id;
END;
$$;

-- Trigger to update analytics cache when evaluations change
CREATE OR REPLACE FUNCTION invalidate_analytics_cache()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE evaluation_analytics_cache
  SET is_stale = true
  WHERE artist_id = NEW.artist_id AND event_id = NEW.event_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER invalidate_cache_on_evaluation_change
  AFTER INSERT OR UPDATE OR DELETE ON artist_scorecard_evaluations
  FOR EACH ROW
  EXECUTE FUNCTION invalidate_analytics_cache();

-- Function to update updated_at timestamps
CREATE OR REPLACE FUNCTION update_scorecard_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_scorecard_evaluations_updated_at
  BEFORE UPDATE ON artist_scorecard_evaluations
  FOR EACH ROW
  EXECUTE FUNCTION update_scorecard_updated_at();

CREATE TRIGGER update_ai_insights_updated_at
  BEFORE UPDATE ON artist_ai_insights
  FOR EACH ROW
  EXECUTE FUNCTION update_scorecard_updated_at();

-- Add unique constraint to AI insights
ALTER TABLE artist_ai_insights
ADD CONSTRAINT unique_artist_event_insights
UNIQUE (artist_id, event_id);

-- Add unique constraint to memorabilia by type
ALTER TABLE digital_memorabilia
ADD CONSTRAINT unique_artist_event_memorabilia_type
UNIQUE (artist_id, event_id, memorabilia_type);