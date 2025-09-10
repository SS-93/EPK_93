-- ===============================================
-- ADVANCED METADATA SYSTEM MIGRATION
-- ===============================================
-- Extends existing schema for advanced metadata features
-- Adds album management, enhanced content metadata, and BSL licensing

-- 1. CRITICAL: Rename artists table to match frontend expectations
ALTER TABLE artists RENAME TO artist_profiles;

-- 2. Update foreign key constraints to use new table name
ALTER TABLE content_items 
DROP CONSTRAINT IF EXISTS content_items_artist_id_fkey,
ADD CONSTRAINT content_items_artist_id_fkey 
FOREIGN KEY (artist_id) REFERENCES artist_profiles(id) ON DELETE CASCADE;

ALTER TABLE subscriptions
DROP CONSTRAINT IF EXISTS subscriptions_artist_id_fkey,
ADD CONSTRAINT subscriptions_artist_id_fkey 
FOREIGN KEY (artist_id) REFERENCES artist_profiles(id) ON DELETE CASCADE;

-- 3. Add advanced metadata columns to content_items
ALTER TABLE content_items ADD COLUMN IF NOT EXISTS
  -- Advanced Details
  buy_link_url TEXT,
  buy_link_title TEXT,
  record_label TEXT,
  release_date DATE,
  publisher TEXT,
  isrc TEXT,
  explicit BOOLEAN DEFAULT false,
  p_line TEXT,
  
  -- Album Linking  
  album_id UUID,
  album_name TEXT,
  track_number INTEGER,
  
  -- Permissions/Access
  enable_direct_downloads BOOLEAN DEFAULT false,
  offline_listening BOOLEAN DEFAULT false,
  include_in_rss BOOLEAN DEFAULT true,
  display_embed_code BOOLEAN DEFAULT true,
  enable_app_playback BOOLEAN DEFAULT true,
  allow_comments BOOLEAN DEFAULT true,
  show_comments_public BOOLEAN DEFAULT true,
  show_insights_public BOOLEAN DEFAULT false,
  
  -- Geoblocking
  availability_scope TEXT DEFAULT 'worldwide' CHECK (availability_scope IN ('worldwide', 'exclusive_regions', 'blocked_regions')),
  availability_regions TEXT[], -- Array of ISO country codes
  
  -- Preview/Clips (stored as JSONB)
  preview_clip JSONB, -- {start_sec, duration_sec}
  visual_clip JSONB, -- {file_path, duration_sec, loop_enabled}
  
  -- Lyrics (stored as JSONB)
  lyrics JSONB, -- {text, synchronized, language, rights_cleared, extracted_metadata, confidence_scores}
  
  -- License Type (including BSL)
  license_type TEXT DEFAULT 'all_rights_reserved' CHECK (license_type IN (
    'all_rights_reserved', 'cc_by', 'cc_by_sa', 'cc_by_nc', 
    'cc_by_nc_sa', 'cc_by_nd', 'cc_by_nc_nd', 'bsl'
  ));

-- 4. Create albums table
CREATE TABLE IF NOT EXISTS albums (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  artist_id UUID NOT NULL REFERENCES artist_profiles(id) ON DELETE CASCADE,
  description TEXT,
  release_date DATE,
  artwork_url TEXT,
  total_tracks INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- 5. Add album foreign key constraint to content_items
ALTER TABLE content_items 
ADD CONSTRAINT content_items_album_id_fkey 
FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE SET NULL;

-- 6. Enhanced artist_profiles for upload features
ALTER TABLE artist_profiles ADD COLUMN IF NOT EXISTS
  record_label TEXT,
  publisher TEXT,
  bsl_enabled BOOLEAN DEFAULT false,
  bsl_tier TEXT CHECK (bsl_tier IN ('basic', 'premium', 'enterprise')),
  upload_preferences JSONB DEFAULT '{}';

-- 7. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_content_items_album_id ON content_items(album_id);
CREATE INDEX IF NOT EXISTS idx_content_items_isrc ON content_items(isrc) WHERE isrc IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_content_items_license ON content_items(license_type);
CREATE INDEX IF NOT EXISTS idx_content_items_availability ON content_items(availability_scope);
CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON albums(artist_id);
CREATE INDEX IF NOT EXISTS idx_albums_release_date ON albums(release_date DESC);

-- 8. Enable RLS on albums table
ALTER TABLE albums ENABLE ROW LEVEL SECURITY;

-- 9. RLS Policies for albums
CREATE POLICY "Artists can manage their albums" ON albums
  FOR ALL USING (
    EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id)
  );

CREATE POLICY "Public can view albums" ON albums
  FOR SELECT USING (true); -- Public album discovery

-- 10. Update content_items RLS to handle new metadata fields
DROP POLICY IF EXISTS "Artists can manage their content" ON content_items;
CREATE POLICY "Artists can manage their content" ON content_items
  FOR ALL USING (
    EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id)
  );

-- 11. Create trigger for albums updated_at
CREATE TRIGGER update_albums_updated_at BEFORE UPDATE ON albums
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 12. Function to auto-increment album track count
CREATE OR REPLACE FUNCTION update_album_track_count()
RETURNS TRIGGER AS $$
BEGIN
  -- When content is added to an album
  IF NEW.album_id IS NOT NULL AND (OLD.album_id IS NULL OR OLD.album_id != NEW.album_id) THEN
    UPDATE albums 
    SET total_tracks = (
      SELECT COUNT(*) FROM content_items WHERE album_id = NEW.album_id
    )
    WHERE id = NEW.album_id;
  END IF;
  
  -- When content is removed from an album
  IF OLD.album_id IS NOT NULL AND (NEW.album_id IS NULL OR OLD.album_id != NEW.album_id) THEN
    UPDATE albums 
    SET total_tracks = (
      SELECT COUNT(*) FROM content_items WHERE album_id = OLD.album_id
    )
    WHERE id = OLD.album_id;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 13. Create trigger for automatic track count updates
CREATE TRIGGER update_album_track_count_trigger
  AFTER INSERT OR UPDATE OR DELETE ON content_items
  FOR EACH ROW EXECUTE FUNCTION update_album_track_count();

-- 14. Function to validate ISRC format
CREATE OR REPLACE FUNCTION validate_isrc_format()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.isrc IS NOT NULL THEN
    -- ISRC format: CC-XXX-YY-NNNNN (12 characters total)
    IF NOT (NEW.isrc ~ '^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$') THEN
      RAISE EXCEPTION 'ISRC must be in format: CC-XXX-YY-NNNNN (Country-Registrant-Year-Designation)';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 15. Create trigger for ISRC validation
CREATE TRIGGER validate_isrc_trigger
  BEFORE INSERT OR UPDATE ON content_items
  FOR EACH ROW EXECUTE FUNCTION validate_isrc_format();

-- 16. Add unique constraint for ISRC (globally unique)
ALTER TABLE content_items ADD CONSTRAINT content_items_isrc_unique UNIQUE(isrc);

-- 17. Create function for BSL license eligibility check
CREATE OR REPLACE FUNCTION check_bsl_eligibility(artist_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  artist_record RECORD;
BEGIN
  SELECT bsl_enabled, verification_status INTO artist_record 
  FROM artist_profiles 
  WHERE id = artist_id;
  
  RETURN (artist_record.bsl_enabled = true AND artist_record.verification_status = 'verified');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 18. Update RLS policies to handle advanced metadata access
CREATE POLICY "Subscribers can view advanced metadata" ON content_items
  FOR SELECT USING (
    -- Check if user has access to this content
    (unlock_date IS NULL OR unlock_date <= now())
    AND (
      -- Content owner
      EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id)
      OR
      -- Subscribed fan
      EXISTS(
        SELECT 1 FROM subscriptions s
        JOIN artist_profiles a ON s.artist_id = a.id
        WHERE s.fan_id = auth.uid()
        AND a.id = artist_id
        AND s.status = 'active'
      )
      OR
      -- Public content
      is_premium = false
    )
  );