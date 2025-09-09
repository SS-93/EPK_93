-- ===============================================
-- FIX STORAGE CONTENT TYPES
-- ===============================================
-- This fixes the content-type metadata for existing audio files in storage

-- Update metadata for WAV files
UPDATE storage.objects 
SET metadata = jsonb_set(
    COALESCE(metadata, '{}'), 
    '{content-type}', 
    '"audio/wav"'
)
WHERE bucket_id = 'artist-content' 
  AND name LIKE '%.wav'
  AND (metadata->>'content-type' IS NULL OR metadata->>'content-type' = 'text/plain');

-- Update metadata for MP3 files  
UPDATE storage.objects 
SET metadata = jsonb_set(
    COALESCE(metadata, '{}'), 
    '{content-type}', 
    '"audio/mpeg"'
)
WHERE bucket_id = 'artist-content' 
  AND name LIKE '%.mp3'
  AND (metadata->>'content-type' IS NULL OR metadata->>'content-type' = 'text/plain');

-- Update metadata for other audio formats
UPDATE storage.objects 
SET metadata = jsonb_set(
    COALESCE(metadata, '{}'), 
    '{content-type}', 
    '"audio/mp4"'
)
WHERE bucket_id = 'artist-content' 
  AND name LIKE '%.m4a'
  AND (metadata->>'content-type' IS NULL OR metadata->>'content-type' = 'text/plain');

UPDATE storage.objects 
SET metadata = jsonb_set(
    COALESCE(metadata, '{}'), 
    '{content-type}', 
    '"audio/flac"'
)
WHERE bucket_id = 'artist-content' 
  AND name LIKE '%.flac'
  AND (metadata->>'content-type' IS NULL OR metadata->>'content-type' = 'text/plain');

-- Verify the updates
SELECT name, metadata->>'content-type' as content_type, created_at
FROM storage.objects 
WHERE bucket_id = 'artist-content'
ORDER BY created_at DESC
LIMIT 10;
