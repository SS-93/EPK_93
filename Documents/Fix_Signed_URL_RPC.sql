-- ===============================================
-- FIX SIGNED URL RPC FUNCTION
-- ===============================================
-- This fixes the RPC function to generate signed URLs for published tracks

-- Drop the existing broken function
DROP FUNCTION IF EXISTS get_published_track_signed_url(UUID, INTEGER);

-- Create a simple function that just validates and returns the file path
-- The client will generate the signed URL
CREATE OR REPLACE FUNCTION get_published_track_path(
    content_id_param UUID
) RETURNS TEXT AS $$
DECLARE
    v_file_path TEXT;
BEGIN
    -- Ensure content exists, is audio, and is published
    SELECT file_path INTO v_file_path
    FROM content_items
    WHERE id = content_id_param
      AND content_type = 'audio'
      AND is_published = true;

    RETURN v_file_path;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
REVOKE ALL ON FUNCTION get_published_track_path(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_published_track_path(UUID) TO anon, authenticated;

-- Test the function (uncomment and replace with actual content_id to test)
-- SELECT get_published_track_path('2d61ee5b-c62f-4a90-8866-798eb9fbca88');
