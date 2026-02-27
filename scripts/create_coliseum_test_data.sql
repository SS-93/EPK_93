-- ============================================================================
-- COLISEUM TEST DATA CREATION SCRIPT
-- ============================================================================
-- Purpose: Create 4 test artists, 16 songs (4 per artist), 2 test users
--          and simulate audio plays to populate leaderboard
-- ============================================================================

-- ============================================================================
-- STEP 1: CREATE TEST ARTISTS
-- ============================================================================

-- Create 4 test artists with different genres/styles
INSERT INTO artist_profiles (
  id,
  user_id,
  artist_name,
  bio,
  verification_status,
  created_at
)
VALUES
  (
    gen_random_uuid(),
    NULL, -- No user account needed for test
    'Test Artist Alpha',
    'Electronic dance music producer specializing in progressive house',
    'verified',
    NOW()
  ),
  (
    gen_random_uuid(),
    NULL,
    'Test Artist Beta',
    'Indie rock band with folk influences',
    'verified',
    NOW()
  ),
  (
    gen_random_uuid(),
    NULL,
    'Test Artist Gamma',
    'Hip-hop artist from the West Coast',
    'verified',
    NOW()
  ),
  (
    gen_random_uuid(),
    NULL,
    'Test Artist Delta',
    'Jazz fusion pianist and composer',
    'verified',
    NOW()
  )
RETURNING id, artist_name;

-- Save artist IDs for later use
-- Note: Copy these IDs from the output above

-- ============================================================================
-- STEP 2: CREATE TEST CONTENT (16 SONGS TOTAL - 4 PER ARTIST)
-- ============================================================================

-- Function to create content for an artist
DO $$
DECLARE
  artist_alpha_id UUID;
  artist_beta_id UUID;
  artist_gamma_id UUID;
  artist_delta_id UUID;
BEGIN
  -- Get artist IDs
  SELECT id INTO artist_alpha_id FROM artist_profiles WHERE artist_name = 'Test Artist Alpha' LIMIT 1;
  SELECT id INTO artist_beta_id FROM artist_profiles WHERE artist_name = 'Test Artist Beta' LIMIT 1;
  SELECT id INTO artist_gamma_id FROM artist_profiles WHERE artist_name = 'Test Artist Gamma' LIMIT 1;
  SELECT id INTO artist_delta_id FROM artist_profiles WHERE artist_name = 'Test Artist Delta' LIMIT 1;

  -- Artist Alpha - Electronic (4 tracks)
  INSERT INTO content_items (
    id,
    artist_id,
    title,
    description,
    content_type,
    file_path,
    duration_seconds,
    is_published,
    metadata,
    created_at
  )
  VALUES
    (
      gen_random_uuid(),
      artist_alpha_id,
      'Alpha Track 1 - Midnight Pulse',
      'High-energy progressive house track',
      'audio',
      'https://example.com/audio/alpha-1.mp3',
      240, -- 4 minutes
      true,
      jsonb_build_object(
        'genre', 'Electronic',
        'subgenre', 'Progressive House',
        'bpm', 128,
        'artist_genres', ARRAY['Electronic', 'House', 'Dance']
      ),
      NOW() - INTERVAL '30 days'
    ),
    (
      gen_random_uuid(),
      artist_alpha_id,
      'Alpha Track 2 - Neon Dreams',
      'Synthwave-inspired electronic track',
      'audio',
      'https://example.com/audio/alpha-2.mp3',
      210,
      true,
      jsonb_build_object(
        'genre', 'Electronic',
        'subgenre', 'Synthwave',
        'bpm', 120,
        'artist_genres', ARRAY['Electronic', 'Synthwave', 'Retro']
      ),
      NOW() - INTERVAL '20 days'
    ),
    (
      gen_random_uuid(),
      artist_alpha_id,
      'Alpha Track 3 - Digital Horizon',
      'Ambient electronic soundscape',
      'audio',
      'https://example.com/audio/alpha-3.mp3',
      300,
      true,
      jsonb_build_object(
        'genre', 'Electronic',
        'subgenre', 'Ambient',
        'bpm', 90,
        'artist_genres', ARRAY['Electronic', 'Ambient', 'Chill']
      ),
      NOW() - INTERVAL '10 days'
    ),
    (
      gen_random_uuid(),
      artist_alpha_id,
      'Alpha Track 4 - Electric Storm',
      'High-energy EDM banger',
      'audio',
      'https://example.com/audio/alpha-4.mp3',
      195,
      true,
      jsonb_build_object(
        'genre', 'Electronic',
        'subgenre', 'EDM',
        'bpm', 140,
        'artist_genres', ARRAY['Electronic', 'EDM', 'Festival']
      ),
      NOW() - INTERVAL '5 days'
    );

  -- Artist Beta - Indie Rock (4 tracks)
  INSERT INTO content_items (
    id,
    artist_id,
    title,
    description,
    content_type,
    file_path,
    duration_seconds,
    is_published,
    metadata,
    created_at
  )
  VALUES
    (
      gen_random_uuid(),
      artist_beta_id,
      'Beta Track 1 - Mountain View',
      'Acoustic indie folk ballad',
      'audio',
      'https://example.com/audio/beta-1.mp3',
      245,
      true,
      jsonb_build_object(
        'genre', 'Indie',
        'subgenre', 'Folk',
        'bpm', 85,
        'artist_genres', ARRAY['Indie', 'Folk', 'Acoustic']
      ),
      NOW() - INTERVAL '28 days'
    ),
    (
      gen_random_uuid(),
      artist_beta_id,
      'Beta Track 2 - City Lights',
      'Upbeat indie rock anthem',
      'audio',
      'https://example.com/audio/beta-2.mp3',
      220,
      true,
      jsonb_build_object(
        'genre', 'Indie',
        'subgenre', 'Rock',
        'bpm', 110,
        'artist_genres', ARRAY['Indie', 'Rock', 'Alternative']
      ),
      NOW() - INTERVAL '18 days'
    ),
    (
      gen_random_uuid(),
      artist_beta_id,
      'Beta Track 3 - Sunset Drive',
      'Dreamy indie pop track',
      'audio',
      'https://example.com/audio/beta-3.mp3',
      195,
      true,
      jsonb_build_object(
        'genre', 'Indie',
        'subgenre', 'Pop',
        'bpm', 100,
        'artist_genres', ARRAY['Indie', 'Pop', 'Dream Pop']
      ),
      NOW() - INTERVAL '12 days'
    ),
    (
      gen_random_uuid(),
      artist_beta_id,
      'Beta Track 4 - Wildfire',
      'Energetic indie rock song',
      'audio',
      'https://example.com/audio/beta-4.mp3',
      230,
      true,
      jsonb_build_object(
        'genre', 'Indie',
        'subgenre', 'Rock',
        'bpm', 115,
        'artist_genres', ARRAY['Indie', 'Rock', 'Garage Rock']
      ),
      NOW() - INTERVAL '7 days'
    );

  -- Artist Gamma - Hip-Hop (4 tracks)
  INSERT INTO content_items (
    id,
    artist_id,
    title,
    description,
    content_type,
    file_path,
    duration_seconds,
    is_published,
    metadata,
    created_at
  )
  VALUES
    (
      gen_random_uuid(),
      artist_gamma_id,
      'Gamma Track 1 - West Coast Flow',
      'Classic West Coast hip-hop',
      'audio',
      'https://example.com/audio/gamma-1.mp3',
      210,
      true,
      jsonb_build_object(
        'genre', 'Hip-Hop',
        'subgenre', 'West Coast',
        'bpm', 95,
        'artist_genres', ARRAY['Hip-Hop', 'Rap', 'West Coast']
      ),
      NOW() - INTERVAL '25 days'
    ),
    (
      gen_random_uuid(),
      artist_gamma_id,
      'Gamma Track 2 - Street Dreams',
      'Hard-hitting trap beat',
      'audio',
      'https://example.com/audio/gamma-2.mp3',
      185,
      true,
      jsonb_build_object(
        'genre', 'Hip-Hop',
        'subgenre', 'Trap',
        'bpm', 140,
        'artist_genres', ARRAY['Hip-Hop', 'Trap', 'Rap']
      ),
      NOW() - INTERVAL '15 days'
    ),
    (
      gen_random_uuid(),
      artist_gamma_id,
      'Gamma Track 3 - Midnight Sessions',
      'Smooth R&B influenced hip-hop',
      'audio',
      'https://example.com/audio/gamma-3.mp3',
      225,
      true,
      jsonb_build_object(
        'genre', 'Hip-Hop',
        'subgenre', 'R&B',
        'bpm', 90,
        'artist_genres', ARRAY['Hip-Hop', 'R&B', 'Soul']
      ),
      NOW() - INTERVAL '8 days'
    ),
    (
      gen_random_uuid(),
      artist_gamma_id,
      'Gamma Track 4 - Power Move',
      'Aggressive rap track',
      'audio',
      'https://example.com/audio/gamma-4.mp3',
      200,
      true,
      jsonb_build_object(
        'genre', 'Hip-Hop',
        'subgenre', 'Rap',
        'bpm', 100,
        'artist_genres', ARRAY['Hip-Hop', 'Rap', 'Hardcore']
      ),
      NOW() - INTERVAL '3 days'
    );

  -- Artist Delta - Jazz (4 tracks)
  INSERT INTO content_items (
    id,
    artist_id,
    title,
    description,
    content_type,
    file_path,
    duration_seconds,
    is_published,
    metadata,
    created_at
  )
  VALUES
    (
      gen_random_uuid(),
      artist_delta_id,
      'Delta Track 1 - Blue Notes',
      'Smooth jazz piano composition',
      'audio',
      'https://example.com/audio/delta-1.mp3',
      320,
      true,
      jsonb_build_object(
        'genre', 'Jazz',
        'subgenre', 'Smooth Jazz',
        'bpm', 70,
        'artist_genres', ARRAY['Jazz', 'Smooth Jazz', 'Piano']
      ),
      NOW() - INTERVAL '22 days'
    ),
    (
      gen_random_uuid(),
      artist_delta_id,
      'Delta Track 2 - Fusion Groove',
      'Jazz fusion with modern elements',
      'audio',
      'https://example.com/audio/delta-2.mp3',
      280,
      true,
      jsonb_build_object(
        'genre', 'Jazz',
        'subgenre', 'Fusion',
        'bpm', 110,
        'artist_genres', ARRAY['Jazz', 'Fusion', 'Progressive']
      ),
      NOW() - INTERVAL '14 days'
    ),
    (
      gen_random_uuid(),
      artist_delta_id,
      'Delta Track 3 - Midnight Swing',
      'Classic swing jazz',
      'audio',
      'https://example.com/audio/delta-3.mp3',
      195,
      true,
      jsonb_build_object(
        'genre', 'Jazz',
        'subgenre', 'Swing',
        'bpm', 180,
        'artist_genres', ARRAY['Jazz', 'Swing', 'Big Band']
      ),
      NOW() - INTERVAL '9 days'
    ),
    (
      gen_random_uuid(),
      artist_delta_id,
      'Delta Track 4 - Modern Standards',
      'Contemporary jazz interpretation',
      'audio',
      'https://example.com/audio/delta-4.mp3',
      265,
      true,
      jsonb_build_object(
        'genre', 'Jazz',
        'subgenre', 'Contemporary',
        'bpm', 85,
        'artist_genres', ARRAY['Jazz', 'Contemporary', 'Modern']
      ),
      NOW() - INTERVAL '4 days'
    );

  RAISE NOTICE '✅ Created 16 test tracks (4 per artist)';
END $$;

-- ============================================================================
-- STEP 3: CREATE TEST USERS (OR USE EXISTING)
-- ============================================================================

-- Check if test users exist, create if needed
DO $$
DECLARE
  test_user_1_id UUID;
  test_user_2_id UUID;
BEGIN
  -- Try to get existing test users or create new ones
  SELECT id INTO test_user_1_id FROM auth.users WHERE email = 'testuser1@coliseum.test' LIMIT 1;
  SELECT id INTO test_user_2_id FROM auth.users WHERE email = 'testuser2@coliseum.test' LIMIT 1;

  -- Note: User creation requires auth.users table access
  -- If users don't exist, you'll need to create them via Supabase Auth API
  -- For now, we'll use existing users or create placeholder references

  IF test_user_1_id IS NULL THEN
    RAISE NOTICE '⚠️ Test User 1 not found. Create via Supabase Auth API or use existing user.';
  ELSE
    RAISE NOTICE '✅ Test User 1 found: %', test_user_1_id;
  END IF;

  IF test_user_2_id IS NULL THEN
    RAISE NOTICE '⚠️ Test User 2 not found. Create via Supabase Auth API or use existing user.';
  ELSE
    RAISE NOTICE '✅ Test User 2 found: %', test_user_2_id;
  END IF;
END $$;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify artists created
SELECT 
  'Artists Created' as check_type,
  COUNT(*) as count
FROM artist_profiles
WHERE artist_name LIKE 'Test Artist%';

-- Verify content created
SELECT 
  'Content Created' as check_type,
  COUNT(*) as total_tracks,
  COUNT(DISTINCT artist_id) as artists_with_content
FROM content_items
WHERE title LIKE '%Track%'
  AND (title LIKE 'Alpha%' OR title LIKE 'Beta%' OR title LIKE 'Gamma%' OR title LIKE 'Delta%');

-- Show summary
SELECT 
  ap.artist_name,
  COUNT(ci.id) as track_count,
  ARRAY_AGG(ci.title ORDER BY ci.created_at) as tracks
FROM artist_profiles ap
LEFT JOIN content_items ci ON ci.artist_id = ap.id
WHERE ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name
ORDER BY ap.artist_name;

-- ============================================================================
-- NEXT STEPS
-- ============================================================================
-- 1. Run this script to create test data
-- 2. Run simulate_audio_plays.sql to create passport events
-- 3. Trigger coliseum processor
-- 4. Check leaderboard
-- ============================================================================
