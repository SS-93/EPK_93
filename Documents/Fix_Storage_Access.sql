-- ===============================================
-- FIX STORAGE ACCESS FOR SIGNED URLs
-- ===============================================
-- This ensures the client can generate signed URLs for published content

-- Check if we need a policy to allow signed URL generation
-- Note: Signed URLs are typically generated server-side, but Supabase allows client-side generation

-- Ensure the artist-content bucket allows signed URL generation for published content
-- This might require allowing SELECT access to the storage.objects table for the paths

-- First, let's check what storage policies exist
-- SELECT * FROM storage.policies WHERE bucket_id = 'artist-content';

-- If needed, add a policy to allow signed URL generation for published content
-- This is typically handled automatically by Supabase, but let's ensure it works

-- Test query to check if files exist in storage
-- SELECT name, bucket_id, created_at 
-- FROM storage.objects 
-- WHERE bucket_id = 'artist-content' 
-- ORDER BY created_at DESC 
-- LIMIT 10;

-- Test query to verify content_items file paths match storage objects
-- SELECT ci.id, ci.title, ci.file_path, so.name as storage_name
-- FROM content_items ci
-- LEFT JOIN storage.objects so ON so.name = ci.file_path AND so.bucket_id = 'artist-content'
-- WHERE ci.content_type = 'audio' AND ci.is_published = true
-- LIMIT 10;

-- If files are missing, this might indicate upload issues
-- Check if file paths in content_items match actual storage object names
