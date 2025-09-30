-- Fix missing profile_image_url columns and ensure all tables have proper photo support

-- Add profile_image_url to event_audience_members if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'event_audience_members'
    AND column_name = 'profile_image_url'
  ) THEN
    ALTER TABLE event_audience_members ADD COLUMN profile_image_url TEXT;
  END IF;
END $$;

-- Add profile_image_url to event_artist_prospects if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'event_artist_prospects'
    AND column_name = 'profile_image_url'
  ) THEN
    ALTER TABLE event_artist_prospects ADD COLUMN profile_image_url TEXT;
  END IF;
END $$;

-- Add bio column to event_artist_prospects if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'event_artist_prospects'
    AND column_name = 'bio'
  ) THEN
    ALTER TABLE event_artist_prospects ADD COLUMN bio TEXT;
  END IF;
END $$;

-- Update RLS policies to ensure public access for event listings
CREATE POLICY IF NOT EXISTS "Public events are viewable by anyone"
  ON events FOR SELECT
  USING (status IN ('published', 'live', 'completed'));

-- Create indexes for global event search
CREATE INDEX IF NOT EXISTS idx_events_public_search
  ON events (status, start_date, created_at)
  WHERE status IN ('published', 'live', 'completed');

CREATE INDEX IF NOT EXISTS idx_events_location_search
  ON events USING gin(to_tsvector('english', COALESCE(location, '')));

CREATE INDEX IF NOT EXISTS idx_events_title_search
  ON events USING gin(to_tsvector('english', title || ' ' || COALESCE(description, '')));

-- Function to get public events for global listing
CREATE OR REPLACE FUNCTION get_public_events(
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0,
  p_search TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_location TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  title TEXT,
  description TEXT,
  location TEXT,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  status TEXT,
  shareable_code TEXT,
  participant_count BIGINT,
  artist_count BIGINT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.id,
    e.title,
    e.description,
    e.location,
    e.start_date,
    e.end_date,
    e.status,
    e.shareable_code,
    COALESCE(audience.count, 0) as participant_count,
    COALESCE(artists.count, 0) as artist_count,
    e.created_at
  FROM events e
  LEFT JOIN (
    SELECT event_id, COUNT(*) as count
    FROM event_audience_members
    GROUP BY event_id
  ) audience ON e.id = audience.event_id
  LEFT JOIN (
    SELECT event_id, COUNT(*) as count
    FROM event_artist_prospects
    WHERE contact_status = 'confirmed'
    GROUP BY event_id
  ) artists ON e.id = artists.event_id
  WHERE
    e.status IN ('published', 'live', 'completed')
    AND (p_search IS NULL OR (
      to_tsvector('english', e.title || ' ' || COALESCE(e.description, ''))
      @@ plainto_tsquery('english', p_search)
    ))
    AND (p_status IS NULL OR e.status = p_status)
    AND (p_location IS NULL OR (
      to_tsvector('english', COALESCE(e.location, ''))
      @@ plainto_tsquery('english', p_location)
    ))
  ORDER BY
    CASE
      WHEN e.status = 'live' THEN 1
      WHEN e.status = 'published' AND e.start_date > NOW() THEN 2
      ELSE 3
    END,
    e.start_date ASC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_public_events TO anon;
GRANT EXECUTE ON FUNCTION get_public_events TO authenticated;