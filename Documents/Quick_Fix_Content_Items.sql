-- Quick fix for content_items table creation
-- Run this if you're getting syntax errors

-- Drop and recreate content_items table with all advanced metadata
DROP TABLE IF EXISTS content_items CASCADE;

CREATE TABLE content_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id UUID REFERENCES artist_profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  content_type content_type NOT NULL,
  file_path TEXT NOT NULL,
  file_size_bytes BIGINT,
  duration_seconds INTEGER,
  unlock_date TIMESTAMP,
  milestone_condition JSONB,
  is_premium BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}',
  
  -- Audio Intelligence fields
  audio_checksum TEXT,
  processing_status TEXT DEFAULT 'pending',
  file_type TEXT,
  duration_ms INTEGER,
  waveform_peaks JSONB,
  
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
  album_id UUID REFERENCES albums(id) ON DELETE SET NULL,
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
  availability_scope TEXT DEFAULT 'worldwide',
  availability_regions TEXT[],
  
  -- Preview/Clips
  preview_clip JSONB,
  visual_clip JSONB,
  
  -- License Type
  license_type TEXT DEFAULT 'all_rights_reserved',
  
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Add constraints separately
ALTER TABLE content_items 
  ADD CONSTRAINT content_items_availability_scope_chk 
  CHECK (availability_scope IN ('worldwide', 'exclusive_regions', 'blocked_regions'));

ALTER TABLE content_items 
  ADD CONSTRAINT content_items_license_type_chk 
  CHECK (license_type IN (
    'all_rights_reserved', 'cc_by', 'cc_by_sa', 'cc_by_nc', 
    'cc_by_nc_sa', 'cc_by_nd', 'cc_by_nc_nd', 'bsl'
  ));

-- Add ISRC unique constraint
ALTER TABLE content_items ADD CONSTRAINT content_items_isrc_unique UNIQUE(isrc);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_content_items_artist ON content_items(artist_id);
CREATE INDEX IF NOT EXISTS idx_content_items_album_id ON content_items(album_id);
CREATE INDEX IF NOT EXISTS idx_content_items_isrc ON content_items(isrc) WHERE isrc IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_content_items_license ON content_items(license_type);
CREATE INDEX IF NOT EXISTS idx_content_items_availability ON content_items(availability_scope);

-- Enable RLS
ALTER TABLE content_items ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Artists can view their content" ON content_items
  FOR SELECT TO public USING (
    EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id)
  );

CREATE POLICY "Artists can insert their content" ON content_items
  FOR INSERT TO public WITH CHECK (
    EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id)
  );

CREATE POLICY "Artists can update their content" ON content_items
  FOR UPDATE TO public 
  USING (EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id))
  WITH CHECK (EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id));

CREATE POLICY "Artists can delete their content" ON content_items
  FOR DELETE TO public USING (
    EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id)
  );

-- Add updated_at trigger
CREATE TRIGGER update_content_items_updated_at BEFORE UPDATE ON content_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();