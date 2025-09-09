-- ===============================================
-- FIX CONTENT SEARCH INDEX RLS
-- ===============================================
-- Purpose: Allow authenticated users to insert/update content_search_index
-- Issue: RLS policy missing for INSERT/UPDATE operations on content_search_index

-- Enable RLS (should already be enabled)
ALTER TABLE content_search_index ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate them properly
DROP POLICY IF EXISTS "Public can search published index" ON content_search_index;
DROP POLICY IF EXISTS "Authenticated users can manage search index" ON content_search_index;

-- Policy for public SELECT access (search functionality)
CREATE POLICY "Public can search published index" ON content_search_index
  FOR SELECT TO public USING (true);

-- Policy for authenticated users to INSERT/UPDATE/DELETE (for triggers and maintenance)
CREATE POLICY "Authenticated users can manage search index" ON content_search_index
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Grant necessary permissions
GRANT SELECT ON content_search_index TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON content_search_index TO authenticated;

-- Ensure the upsert function has proper permissions
GRANT EXECUTE ON FUNCTION upsert_content_search_index(UUID) TO authenticated;

-- ===============================================
-- END FIX
-- ===============================================
