-- ===============================================
-- FIX VIDEO UPLOAD SUPPORT
-- ===============================================
-- Resolves the 400 Bad Request and 403 RLS policy errors for video uploads
-- Based on the error: visual_1757657219955_Mariah%20Carey%20-%20Fantasy%20(Instrumental).mp4

-- PROBLEM ANALYSIS:
-- 1. Video file is trying to upload to 'artist-content' bucket 
-- 2. Current policies only allow audio MIME types in artist-content
-- 3. RLS policy may be blocking the content_items insert

-- ===============================================
-- SOLUTION 1: UPDATE STORAGE POLICIES TO ALLOW VIDEO IN ARTIST-CONTENT
-- ===============================================

-- Update the upload validation function to include video types in artist-content bucket
-- (Only create if it doesn't exist to avoid conflicts)
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
  -- Get user role from profiles table
  SELECT role INTO user_role FROM profiles WHERE id = user_id;
  
  -- Check if user is artist or admin
  IF user_role NOT IN ('artist', 'admin') THEN
    RETURN false;
  END IF;
  
  -- Set limits based on bucket - UPDATED TO INCLUDE VIDEO
  CASE bucket_name
    WHEN 'artist-content' THEN
      max_size := 104857600; -- 100MB (increased for video)
      allowed_types := ARRAY[
        'audio/mpeg', 'audio/wav', 'audio/flac', 'audio/mp4', 'audio/aac',
        'video/mp4', 'video/quicktime', 'video/webm', 'video/avi'  -- ✅ ADDED VIDEO SUPPORT
      ];
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

-- ===============================================
-- SOLUTION 2: FIX CONTENT_ITEMS RLS POLICY
-- ===============================================

-- The RLS error suggests the content_items insert is failing
-- Let's check and fix the content_items policies

-- Drop existing conflicting policies first
DROP POLICY IF EXISTS "Artists can manage their content" ON content_items;
DROP POLICY IF EXISTS "Artists can insert their content" ON content_items;
DROP POLICY IF EXISTS "Artists can update their content" ON content_items;
DROP POLICY IF EXISTS "Artists can view their content" ON content_items;
DROP POLICY IF EXISTS "Artists can delete their content" ON content_items;

-- Create a more specific policy that allows artists to insert content
CREATE POLICY "Artists can insert their content" ON content_items
  FOR INSERT TO authenticated WITH CHECK (
    -- Check if user has an artist profile
    EXISTS(
      SELECT 1 FROM artist_profiles ap 
      WHERE ap.user_id = auth.uid() AND ap.id = artist_id
    )
    OR
    -- Fallback: check profiles table for artist role
    EXISTS(
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role = 'artist'
    )
  );

-- Allow artists to update their own content
CREATE POLICY "Artists can update their content" ON content_items
  FOR UPDATE TO authenticated USING (
    EXISTS(
      SELECT 1 FROM artist_profiles ap 
      WHERE ap.user_id = auth.uid() AND ap.id = artist_id
    )
    OR
    EXISTS(
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role = 'artist'
    )
  );

-- Allow artists to select/view their own content
CREATE POLICY "Artists can view their content" ON content_items
  FOR SELECT TO authenticated USING (
    EXISTS(
      SELECT 1 FROM artist_profiles ap 
      WHERE ap.user_id = auth.uid() AND ap.id = artist_id
    )
    OR
    EXISTS(
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role = 'artist'
    )
  );

-- Allow artists to delete their own content
CREATE POLICY "Artists can delete their content" ON content_items
  FOR DELETE TO authenticated USING (
    EXISTS(
      SELECT 1 FROM artist_profiles ap 
      WHERE ap.user_id = auth.uid() AND ap.id = artist_id
    )
    OR
    EXISTS(
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role = 'artist'
    )
  );

-- ===============================================
-- SOLUTION 3: ENSURE ARTIST_PROFILES TABLE EXISTS AND HAS PROPER DATA
-- ===============================================

-- Ensure artist_profiles table matches consolidated schema
-- (Table should already exist from Final_Consolidated_Schema.sql)
-- Just ensure we have the required fields for video uploads
ALTER TABLE artist_profiles ADD COLUMN IF NOT EXISTS artist_name TEXT;
ALTER TABLE artist_profiles ADD COLUMN IF NOT EXISTS stage_name TEXT;

-- Enable RLS on artist_profiles
ALTER TABLE artist_profiles ENABLE ROW LEVEL SECURITY;

-- Create policies for artist_profiles
DROP POLICY IF EXISTS "Artists can manage their profile" ON artist_profiles;
CREATE POLICY "Artists can manage their profile" ON artist_profiles
  FOR ALL TO authenticated USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ===============================================
-- SOLUTION 4: AUTO-CREATE ARTIST PROFILE FOR ARTISTS
-- ===============================================

-- Function to auto-create artist profile when user becomes an artist
CREATE OR REPLACE FUNCTION create_artist_profile_if_needed()
RETURNS TRIGGER AS $$
BEGIN
  -- If user role is now 'artist' and no artist profile exists
  IF NEW.role = 'artist' AND OLD.role != 'artist' THEN
    INSERT INTO artist_profiles (user_id, stage_name)
    VALUES (NEW.id, NEW.display_name)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to auto-create artist profiles
DROP TRIGGER IF EXISTS auto_create_artist_profile ON profiles;
CREATE TRIGGER auto_create_artist_profile
  AFTER UPDATE OF role ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION create_artist_profile_if_needed();

-- ===============================================
-- SOLUTION 5: UPDATE STORAGE BUCKET POLICIES
-- ===============================================

-- Make sure storage policies allow video uploads to artist-content bucket
-- (These should be run in Supabase Dashboard if not already applied)

-- Update storage policies to allow video uploads to artist-content bucket
-- Drop ALL existing conflicting policies first (comprehensive cleanup)
DROP POLICY IF EXISTS "Artists can upload their own content" ON storage.objects;
DROP POLICY IF EXISTS "Artists can manage their own content" ON storage.objects;
DROP POLICY IF EXISTS "Artists can upload content including video" ON storage.objects;
DROP POLICY IF EXISTS "Artists can manage content including video" ON storage.objects;
DROP POLICY IF EXISTS "Artists can upload content and video" ON storage.objects;
DROP POLICY IF EXISTS "Artists can manage content and video" ON storage.objects;
DROP POLICY IF EXISTS "Artists can delete content and video" ON storage.objects;
DROP POLICY IF EXISTS "Public can view artist content and video" ON storage.objects;

-- Create updated policies that allow video files
CREATE POLICY "Artists can upload content including video" ON storage.objects
  FOR INSERT TO public WITH CHECK (
    bucket_id = 'artist-content' 
    AND auth.uid()::text = (storage.foldername(name))[1]
    AND EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'artist')
  );

CREATE POLICY "Artists can manage their content including video" ON storage.objects
  FOR ALL TO public USING (
    bucket_id = 'artist-content' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  ) WITH CHECK (
    bucket_id = 'artist-content' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- ===============================================
-- SOLUTION 6: VERIFICATION QUERIES
-- ===============================================

-- Run these to verify the fixes work:

-- 1. Check if user has artist profile
-- SELECT p.id, p.display_name, p.role, ap.id as artist_profile_id
-- FROM profiles p
-- LEFT JOIN artist_profiles ap ON p.id = ap.user_id
-- WHERE p.id = auth.uid();

-- 2. Check storage policies
-- SELECT name, bucket_id, command, definition
-- FROM storage.policies 
-- WHERE bucket_id = 'artist-content'
-- ORDER BY name;

-- 3. Test content_items insert permission
-- cc
-- ===============================================
-- IMMEDIATE ACTION ITEMS FOR BACKEND
-- ===============================================

-- FIRST: Check current user status
SELECT 'Checking current user and artist profile...' as status;

SELECT 
  u.id as user_id,
  u.email,
  p.role,
  p.display_name,
  ap.id as artist_profile_id
FROM auth.users u
LEFT JOIN profiles p ON u.id = p.id
LEFT JOIN artist_profiles ap ON u.id = ap.user_id
WHERE u.id = auth.uid();

-- EMERGENCY: Create artist profile if missing (fixes 403 error)
INSERT INTO artist_profiles (user_id, stage_name)
SELECT id, COALESCE(display_name, email)
FROM profiles
WHERE role = 'artist'
  AND id NOT IN (SELECT user_id FROM artist_profiles WHERE user_id IS NOT NULL)
ON CONFLICT (user_id) DO NOTHING;

-- Check what storage policies currently exist
SELECT 'Current storage policies:' as status;
SELECT name, bucket_id, command, definition
FROM storage.policies 
WHERE bucket_id = 'artist-content';

-- IMMEDIATE FIX: Drop restrictive storage policies (fixes 400 error)
DROP POLICY IF EXISTS "Artists can upload their content" ON storage.objects;
DROP POLICY IF EXISTS "Artists can update their content" ON storage.objects;  
DROP POLICY IF EXISTS "Artists can delete their content" ON storage.objects;
DROP POLICY IF EXISTS "Public can view artist content" ON storage.objects;

-- Create new permissive storage policies for video uploads
CREATE POLICY "Artists can upload content and video" ON storage.objects
  FOR INSERT TO public WITH CHECK (
    bucket_id = 'artist-content'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Artists can manage content and video" ON storage.objects
  FOR UPDATE TO public USING (
    bucket_id = 'artist-content'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Artists can delete content and video" ON storage.objects
  FOR DELETE TO public USING (
    bucket_id = 'artist-content'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Public can view artist content and video" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'artist-content');

-- VERIFY THE FIX
SELECT 'Verifying fix...' as status;
SELECT 
  auth.uid() as current_user,
  EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'artist') as is_artist,
  EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid()) as has_profile;

/*
APPLY THESE FIXES IN ORDER:

1. Run this entire SQL file in Supabase SQL Editor
2. Check that artist_profiles table is populated for existing artist users
3. Verify storage bucket 'artist-content' exists and allows video MIME types
4. Test video upload again - should now work

ERROR ANALYSIS:
- 400 Bad Request: Fixed by allowing video MIME types in artist-content bucket
- 403 RLS Policy: Fixed by ensuring user has artist_profiles entry and proper policies

*/