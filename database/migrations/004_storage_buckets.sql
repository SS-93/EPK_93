-- ===============================================
-- STORAGE BUCKETS CONFIGURATION
-- ===============================================
-- Configure storage buckets for advanced metadata features

-- 1. Create storage buckets (Note: Run these in Supabase Dashboard -> Storage)
-- Or use the following as reference for manual creation:

/*
BUCKET CONFIGURATIONS TO CREATE IN SUPABASE DASHBOARD:

1. ARTIST-CONTENT BUCKET
   - ID: artist-content  
   - Public: true
   - File size limit: 52MB (52428800 bytes)
   - Allowed MIME types: audio/mpeg, audio/wav, audio/flac, audio/mp4, audio/aac

2. VISUAL-CLIPS BUCKET
   - ID: visual-clips
   - Public: true  
   - File size limit: 52MB (52428800 bytes)
   - Allowed MIME types: video/mp4, video/quicktime, video/webm, video/avi

3. LYRICS-DOCUMENTS BUCKET
   - ID: lyrics-documents
   - Public: false
   - File size limit: 10MB (10485760 bytes)
   - Allowed MIME types: text/plain, application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document
*/

-- 2. Storage RLS Policies

-- Policy: Artists can upload their content to artist-content bucket
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can upload their content',
  'artist-content',
  'INSERT',
  '((bucket_id = ''artist-content''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can update their content in artist-content bucket  
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can update their content',
  'artist-content', 
  'UPDATE',
  '((bucket_id = ''artist-content''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can delete their content from artist-content bucket
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can delete their content',
  'artist-content',
  'DELETE', 
  '((bucket_id = ''artist-content''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Public can view artist content
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Public can view artist content',
  'artist-content',
  'SELECT',
  '(bucket_id = ''artist-content''::text)'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can upload visual clips
INSERT INTO storage.policies (name, bucket_id, command, definition) 
VALUES (
  'Artists can upload visual clips',
  'visual-clips',
  'INSERT',
  '((bucket_id = ''visual-clips''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can update their visual clips
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can update their visual clips', 
  'visual-clips',
  'UPDATE',
  '((bucket_id = ''visual-clips''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can delete their visual clips
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can delete their visual clips',
  'visual-clips',
  'DELETE',
  '((bucket_id = ''visual-clips''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Public can view visual clips
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Public can view visual clips',
  'visual-clips', 
  'SELECT',
  '(bucket_id = ''visual-clips''::text)'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can upload lyrics documents
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can upload lyrics documents',
  'lyrics-documents',
  'INSERT', 
  '((bucket_id = ''lyrics-documents''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can view their lyrics documents
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can view their lyrics documents',
  'lyrics-documents',
  'SELECT',
  '((bucket_id = ''lyrics-documents''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can update their lyrics documents  
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can update their lyrics documents',
  'lyrics-documents',
  'UPDATE',
  '((bucket_id = ''lyrics-documents''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- Policy: Artists can delete their lyrics documents
INSERT INTO storage.policies (name, bucket_id, command, definition)
VALUES (
  'Artists can delete their lyrics documents', 
  'lyrics-documents',
  'DELETE',
  '((bucket_id = ''lyrics-documents''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))'
) ON CONFLICT DO NOTHING;

-- 3. Create storage helper functions

-- Function to get storage URL for a file
CREATE OR REPLACE FUNCTION get_storage_url(bucket_name TEXT, file_path TEXT)
RETURNS TEXT AS $$
DECLARE
  base_url TEXT;
BEGIN
  -- Get Supabase URL from environment or use default
  base_url := COALESCE(current_setting('app.supabase_url', true), 'http://localhost:54321');
  RETURN base_url || '/storage/v1/object/public/' || bucket_name || '/' || file_path;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to generate unique file name
CREATE OR REPLACE FUNCTION generate_unique_filename(user_id UUID, original_filename TEXT)
RETURNS TEXT AS $$
DECLARE
  extension TEXT;
  timestamp_str TEXT;
  random_suffix TEXT;
BEGIN
  -- Extract file extension
  extension := substring(original_filename from '\.([^.]*)$');
  
  -- Generate timestamp string
  timestamp_str := to_char(now(), 'YYYYMMDDHH24MISS');
  
  -- Generate random suffix
  random_suffix := encode(gen_random_bytes(4), 'hex');
  
  -- Return format: {user_id}/{timestamp}_{random}.{extension}
  RETURN user_id::text || '/' || timestamp_str || '_' || random_suffix || COALESCE('.' || extension, '');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to validate file upload permissions
CREATE OR REPLACE FUNCTION can_upload_file(
  user_id UUID, 
  bucket_name TEXT, 
  file_size BIGINT,
  mime_type TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
  user_role TEXT;
  max_size BIGINT;
  allowed_types TEXT[];
BEGIN
  -- Get user role
  SELECT role INTO user_role FROM profiles WHERE id = user_id;
  
  -- Check if user is artist or admin
  IF user_role NOT IN ('artist', 'admin') THEN
    RETURN false;
  END IF;
  
  -- Set limits based on bucket
  CASE bucket_name
    WHEN 'artist-content' THEN
      max_size := 52428800; -- 50MB
      allowed_types := ARRAY['audio/mpeg', 'audio/wav', 'audio/flac', 'audio/mp4', 'audio/aac'];
    WHEN 'visual-clips' THEN  
      max_size := 52428800; -- 50MB
      allowed_types := ARRAY['video/mp4', 'video/quicktime', 'video/webm', 'video/avi'];
    WHEN 'lyrics-documents' THEN
      max_size := 10485760; -- 10MB
      allowed_types := ARRAY['text/plain', 'application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'];
    ELSE
      RETURN false;
  END CASE;
  
  -- Check file size
  IF file_size > max_size THEN
    RETURN false;
  END IF;
  
  -- Check MIME type
  IF NOT (mime_type = ANY(allowed_types)) THEN
    RETURN false;
  END IF;
  
  RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create content upload log table for tracking
CREATE TABLE IF NOT EXISTS content_upload_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content_item_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  bucket_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_size BIGINT NOT NULL,
  mime_type TEXT NOT NULL,
  upload_status TEXT DEFAULT 'pending' CHECK (upload_status IN ('pending', 'completed', 'failed', 'processing')),
  error_message TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Enable RLS on upload log
ALTER TABLE content_upload_log ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own upload logs
CREATE POLICY "Users can view their upload logs" ON content_upload_log
  FOR SELECT USING (auth.uid() = user_id);

-- Policy: System can manage upload logs
CREATE POLICY "System can manage upload logs" ON content_upload_log
  FOR ALL USING (true); -- Managed by backend services

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_content_upload_log_user ON content_upload_log(user_id);
CREATE INDEX IF NOT EXISTS idx_content_upload_log_status ON content_upload_log(upload_status);
CREATE INDEX IF NOT EXISTS idx_content_upload_log_created ON content_upload_log(created_at DESC);

-- Add updated_at trigger
CREATE TRIGGER update_content_upload_log_updated_at BEFORE UPDATE ON content_upload_log
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();