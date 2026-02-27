-- ============================================================================
-- SIMULATE AUDIO PLAYS FOR COLISEUM TESTING
-- ============================================================================
-- Purpose: Create passport events simulating 2 users playing tracks
--          This will affect artist rankings on the leaderboard
-- ============================================================================

-- ============================================================================
-- STEP 1: GET TEST DATA IDs
-- ============================================================================

DO $$
DECLARE
  -- Artist IDs
  artist_alpha_id UUID;
  artist_beta_id UUID;
  artist_gamma_id UUID;
  artist_delta_id UUID;
  
  -- Track IDs (one per artist for simplicity)
  alpha_track_1_id UUID;
  beta_track_1_id UUID;
  gamma_track_1_id UUID;
  delta_track_1_id UUID;
  
  -- User IDs (use existing or create references)
  test_user_1_id UUID;
  test_user_2_id UUID;
  
  play_count INTEGER := 0;
BEGIN
  -- Get artist IDs
  SELECT id INTO artist_alpha_id FROM artist_profiles WHERE artist_name = 'Test Artist Alpha' LIMIT 1;
  SELECT id INTO artist_beta_id FROM artist_profiles WHERE artist_name = 'Test Artist Beta' LIMIT 1;
  SELECT id INTO artist_gamma_id FROM artist_profiles WHERE artist_name = 'Test Artist Gamma' LIMIT 1;
  SELECT id INTO artist_delta_id FROM artist_profiles WHERE artist_name = 'Test Artist Delta' LIMIT 1;

  -- Get track IDs (first track from each artist)
  SELECT id INTO alpha_track_1_id FROM content_items WHERE artist_id = artist_alpha_id ORDER BY created_at LIMIT 1;
  SELECT id INTO beta_track_1_id FROM content_items WHERE artist_id = artist_beta_id ORDER BY created_at LIMIT 1;
  SELECT id INTO gamma_track_1_id FROM content_items WHERE artist_id = artist_gamma_id ORDER BY created_at LIMIT 1;
  SELECT id INTO delta_track_1_id FROM content_items WHERE artist_id = artist_delta_id ORDER BY created_at LIMIT 1;

  -- Get user IDs (use first 2 users, or create test users)
  SELECT id INTO test_user_1_id FROM auth.users ORDER BY created_at LIMIT 1 OFFSET 0;
  SELECT id INTO test_user_2_id FROM auth.users ORDER BY created_at LIMIT 1 OFFSET 1;

  -- If not enough users, use same user for both
  IF test_user_2_id IS NULL THEN
    test_user_2_id := test_user_1_id;
  END IF;

  RAISE NOTICE 'Using User 1: %', test_user_1_id;
  RAISE NOTICE 'Using User 2: %', test_user_2_id;
  RAISE NOTICE 'Artist Alpha: %', artist_alpha_id;
  RAISE NOTICE 'Artist Beta: %', artist_beta_id;
  RAISE NOTICE 'Artist Gamma: %', artist_gamma_id;
  RAISE NOTICE 'Artist Delta: %', artist_delta_id;

  -- ============================================================================
  -- STEP 2: SIMULATE PLAYS - USER 1 (Heavy Alpha & Beta listener)
  -- ============================================================================
  
  -- User 1 plays Alpha tracks heavily (10 plays - should boost Alpha ranking)
  FOR i IN 1..10 LOOP
    INSERT INTO passport_entries (
      user_id,
      event_type,
      event_category,
      entity_type,
      entity_id,
      metadata,
      created_at,
      processed_by_coliseum
    )
    VALUES (
      test_user_1_id,
      'player.track_played',
      'player',
      'artist',
      artist_alpha_id,
      jsonb_build_object(
        'artistId', artist_alpha_id,
        'artistName', 'Test Artist Alpha',
        'trackId', alpha_track_1_id,
        'trackTitle', 'Alpha Track 1 - Midnight Pulse',
        'source', 'web',
        'duration_seconds', 180 + (i * 10), -- Varying play durations
        'total_duration_seconds', 240,
        'progress_percentage', CASE 
          WHEN i <= 5 THEN 75.0  -- Partial plays
          ELSE 95.0               -- Near-complete plays (higher weight)
        END,
        'is_repeat_play', i > 1,
        'artist_genres', ARRAY['Electronic', 'House', 'Dance']
      ),
      NOW() - INTERVAL '1 day' + (i || ' hours')::interval,
      false
    );
    play_count := play_count + 1;
  END LOOP;

  -- User 1 plays Beta tracks moderately (5 plays)
  FOR i IN 1..5 LOOP
    INSERT INTO passport_entries (
      user_id,
      event_type,
      event_category,
      entity_type,
      entity_id,
      metadata,
      created_at,
      processed_by_coliseum
    )
    VALUES (
      test_user_1_id,
      'player.track_played',
      'player',
      'artist',
      artist_beta_id,
      jsonb_build_object(
        'artistId', artist_beta_id,
        'artistName', 'Test Artist Beta',
        'trackId', beta_track_1_id,
        'trackTitle', 'Beta Track 1 - Mountain View',
        'source', 'web',
        'duration_seconds', 200,
        'total_duration_seconds', 245,
        'progress_percentage', 80.0,
        'is_repeat_play', i > 1,
        'artist_genres', ARRAY['Indie', 'Folk', 'Acoustic']
      ),
      NOW() - INTERVAL '12 hours' + (i || ' hours')::interval,
      false
    );
    play_count := play_count + 1;
  END LOOP;

  -- User 1 plays Gamma once (low engagement)
  INSERT INTO passport_entries (
    user_id,
    event_type,
    event_category,
    entity_type,
    entity_id,
    metadata,
    created_at,
    processed_by_coliseum
  )
  VALUES (
    test_user_1_id,
    'player.track_played',
    'player',
    'artist',
    artist_gamma_id,
    jsonb_build_object(
      'artistId', artist_gamma_id,
      'artistName', 'Test Artist Gamma',
      'trackId', gamma_track_1_id,
      'trackTitle', 'Gamma Track 1 - West Coast Flow',
      'source', 'web',
      'duration_seconds', 30, -- Short play (low engagement)
      'total_duration_seconds', 210,
      'progress_percentage', 14.0,
      'is_repeat_play', false,
      'artist_genres', ARRAY['Hip-Hop', 'Rap', 'West Coast']
    ),
    NOW() - INTERVAL '6 hours',
    false
  );
  play_count := play_count + 1;

  -- ============================================================================
  -- STEP 3: SIMULATE PLAYS - USER 2 (Heavy Gamma & Delta listener)
  -- ============================================================================
  
  -- User 2 plays Gamma tracks heavily (12 plays - should boost Gamma ranking)
  FOR i IN 1..12 LOOP
    INSERT INTO passport_entries (
      user_id,
      event_type,
      event_category,
      entity_type,
      entity_id,
      metadata,
      created_at,
      processed_by_coliseum
    )
    VALUES (
      test_user_2_id,
      'player.track_played',
      'player',
      'artist',
      artist_gamma_id,
      jsonb_build_object(
        'artistId', artist_gamma_id,
        'artistName', 'Test Artist Gamma',
        'trackId', gamma_track_1_id,
        'trackTitle', 'Gamma Track 1 - West Coast Flow',
        'source', 'web',
        'duration_seconds', CASE 
          WHEN i <= 6 THEN 150  -- Partial plays
          ELSE 200              -- Complete plays (higher weight)
        END,
        'total_duration_seconds', 210,
        'progress_percentage', CASE 
          WHEN i <= 6 THEN 71.0
          ELSE 95.0
        END,
        'is_repeat_play', i > 1,
        'artist_genres', ARRAY['Hip-Hop', 'Rap', 'West Coast']
      ),
      NOW() - INTERVAL '18 hours' + (i || ' hours')::interval,
      false
    );
    play_count := play_count + 1;
  END LOOP;

  -- User 2 plays Delta tracks moderately (7 plays)
  FOR i IN 1..7 LOOP
    INSERT INTO passport_entries (
      user_id,
      event_type,
      event_category,
      entity_type,
      entity_id,
      metadata,
      created_at,
      processed_by_coliseum
    )
    VALUES (
      test_user_2_id,
      'player.track_played',
      'player',
      'artist',
      artist_delta_id,
      jsonb_build_object(
        'artistId', artist_delta_id,
        'artistName', 'Test Artist Delta',
        'trackId', delta_track_1_id,
        'trackTitle', 'Delta Track 1 - Blue Notes',
        'source', 'web',
        'duration_seconds', 250,
        'total_duration_seconds', 320,
        'progress_percentage', 78.0,
        'is_repeat_play', i > 1,
        'artist_genres', ARRAY['Jazz', 'Smooth Jazz', 'Piano']
      ),
      NOW() - INTERVAL '10 hours' + (i || ' hours')::interval,
      false
    );
    play_count := play_count + 1;
  END LOOP;

  -- User 2 plays Alpha once (low engagement)
  INSERT INTO passport_entries (
    user_id,
    event_type,
    event_category,
    entity_type,
    entity_id,
    metadata,
    created_at,
    processed_by_coliseum
  )
  VALUES (
    test_user_2_id,
    'player.track_played',
    'player',
    'artist',
    artist_alpha_id,
    jsonb_build_object(
      'artistId', artist_alpha_id,
      'artistName', 'Test Artist Alpha',
      'trackId', alpha_track_1_id,
      'trackTitle', 'Alpha Track 1 - Midnight Pulse',
      'source', 'web',
      'duration_seconds', 45, -- Short play
      'total_duration_seconds', 240,
      'progress_percentage', 18.0,
      'is_repeat_play', false,
      'artist_genres', ARRAY['Electronic', 'House', 'Dance']
    ),
    NOW() - INTERVAL '4 hours',
    false
  );
  play_count := play_count + 1;

  RAISE NOTICE '✅ Created % passport events simulating audio plays', play_count;
  RAISE NOTICE '';
  RAISE NOTICE 'Expected Rankings (after processing):';
  RAISE NOTICE '  1. Test Artist Gamma (12 plays from User 2)';
  RAISE NOTICE '  2. Test Artist Alpha (10 plays from User 1)';
  RAISE NOTICE '  3. Test Artist Delta (7 plays from User 2)';
  RAISE NOTICE '  4. Test Artist Beta (5 plays from User 1)';
  RAISE NOTICE '';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '  1. Trigger coliseum processor';
  RAISE NOTICE '  2. Check leaderboard rankings';
  RAISE NOTICE '  3. Verify rankings match expected order';

END $$;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check events created
SELECT 
  'Events Created' as check_type,
  COUNT(*) as total_events,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT entity_id) as unique_artists
FROM passport_entries
WHERE event_type = 'player.track_played'
  AND created_at > NOW() - INTERVAL '2 days'
  AND entity_id IN (
    SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
  );

-- Show play distribution by artist
SELECT 
  ap.artist_name,
  COUNT(*) as play_count,
  COUNT(DISTINCT pe.user_id) as unique_listeners,
  AVG((pe.metadata->>'progress_percentage')::numeric) as avg_completion_pct,
  COUNT(*) FILTER (WHERE (pe.metadata->>'is_repeat_play')::boolean = true) as repeat_plays
FROM passport_entries pe
JOIN artist_profiles ap ON ap.id = pe.entity_id
WHERE pe.event_type = 'player.track_played'
  AND pe.created_at > NOW() - INTERVAL '2 days'
  AND ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name
ORDER BY play_count DESC;

-- Show play distribution by user
SELECT 
  pe.user_id,
  COUNT(*) as play_count,
  COUNT(DISTINCT pe.entity_id) as artists_listened_to,
  ARRAY_AGG(DISTINCT ap.artist_name) as artists
FROM passport_entries pe
JOIN artist_profiles ap ON ap.id = pe.entity_id
WHERE pe.event_type = 'player.track_played'
  AND pe.created_at > NOW() - INTERVAL '2 days'
  AND ap.artist_name LIKE 'Test Artist%'
GROUP BY pe.user_id
ORDER BY play_count DESC;
