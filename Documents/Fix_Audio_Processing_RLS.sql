-- ===============================================
-- FIX AUDIO PROCESSING JOBS RLS POLICY
-- ===============================================
-- This fixes the RLS policy to allow artists to insert audio processing jobs

-- Drop existing restrictive policy
DROP POLICY IF EXISTS "System can manage processing jobs" ON audio_processing_jobs;

-- Create policies that allow artists to insert processing jobs for their own content
DROP POLICY IF EXISTS "Artists can insert processing jobs" ON audio_processing_jobs;
CREATE POLICY "Artists can insert processing jobs" ON audio_processing_jobs
    FOR INSERT TO authenticated WITH CHECK (
        EXISTS(
            SELECT 1 FROM content_items ci
            JOIN artist_profiles ap ON ci.artist_id = ap.id
            WHERE ci.id = content_id AND ap.user_id = auth.uid()
        )
        OR
        EXISTS(
            SELECT 1 FROM content_items ci
            JOIN artists a ON ci.artist_id = a.id
            WHERE ci.id = content_id AND a.user_id = auth.uid()
        )
    );

-- Re-create system policy for service role
CREATE POLICY "System can manage processing jobs" ON audio_processing_jobs
    FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Also allow artists to view their processing jobs
DROP POLICY IF EXISTS "Artists can view their content processing jobs" ON audio_processing_jobs;
CREATE POLICY "Artists can view their content processing jobs" ON audio_processing_jobs
    FOR SELECT TO authenticated USING (
        EXISTS(
            SELECT 1 FROM content_items ci
            JOIN artist_profiles ap ON ci.artist_id = ap.id
            WHERE ci.id = content_id AND ap.user_id = auth.uid()
        )
        OR
        EXISTS(
            SELECT 1 FROM content_items ci
            JOIN artists a ON ci.artist_id = a.id
            WHERE ci.id = content_id AND a.user_id = auth.uid()
        )
    );
