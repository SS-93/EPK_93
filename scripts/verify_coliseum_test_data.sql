-- ============================================================================
-- VERIFY COLISEUM TEST DATA AND RANKINGS
-- ============================================================================
-- Purpose: Verify test data setup and check leaderboard rankings
-- ============================================================================

-- ============================================================================
-- STEP 1: VERIFY TEST DATA EXISTS
-- ============================================================================

SELECT 
  '=== TEST DATA VERIFICATION ===' as section;

-- Artists
SELECT 
  'Artists' as check_type,
  COUNT(*) as count,
  ARRAY_AGG(artist_name ORDER BY artist_name) as names
FROM artist_profiles
WHERE artist_name LIKE 'Test Artist%';

-- Content
SELECT 
  'Content Items' as check_type,
  COUNT(*) as total_tracks,
  COUNT(DISTINCT artist_id) as artists_with_content
FROM content_items
WHERE title LIKE '%Track%'
  AND (title LIKE 'Alpha%' OR title LIKE 'Beta%' OR title LIKE 'Gamma%' OR title LIKE 'Delta%');

-- Passport Events
SELECT 
  'Passport Events' as check_type,
  COUNT(*) as total_events,
  COUNT(*) FILTER (WHERE coliseum_processed_at IS NULL) as unprocessed,
  COUNT(*) FILTER (WHERE coliseum_processed_at IS NOT NULL) as processed
FROM passport_entries
WHERE event_type = 'player.track_played'
  AND entity_id IN (
    SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
  );

-- ============================================================================
-- STEP 2: CHECK MUTATIONS CREATED
-- ============================================================================

SELECT 
  '=== MUTATIONS VERIFICATION ===' as section;

-- Mutations by domain
SELECT 
  domain,
  COUNT(*) as mutation_count,
  COUNT(DISTINCT artist_id) as artists_affected,
  ROUND(SUM(effective_delta), 2) as total_strength,
  ROUND(AVG(weight), 2) as avg_weight
FROM coliseum_dna_mutations
WHERE artist_id IN (
  SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
)
GROUP BY domain
ORDER BY domain;

-- Mutations by artist
SELECT 
  ap.artist_name,
  domain,
  COUNT(*) as mutation_count,
  ROUND(SUM(effective_delta), 2) as total_strength
FROM coliseum_dna_mutations cm
JOIN artist_profiles ap ON ap.id = cm.artist_id
WHERE ap.artist_name LIKE 'Test Artist%'
GROUP BY ap.id, ap.artist_name, domain
ORDER BY ap.artist_name, domain;

-- ============================================================================
-- STEP 3: CHECK DOMAIN STRENGTH
-- ============================================================================

SELECT 
  '=== DOMAIN STRENGTH VERIFICATION ===' as section;

-- Domain strength by artist (7d)
SELECT 
  ap.artist_name,
  ds.time_range,
  ROUND(ds.a_strength, 2) as a_strength,
  ROUND(ds.t_strength, 2) as t_strength,
  ROUND(ds.g_strength, 2) as g_strength,
  ROUND(ds.c_strength, 2) as c_strength,
  ROUND(ds.a_strength + ds.t_strength + ds.g_strength + ds.c_strength, 2) as total_strength,
  ds.calculated_at
FROM coliseum_domain_strength ds
JOIN artist_profiles ap ON ap.id = ds.entity_id
WHERE ap.artist_name LIKE 'Test Artist%'
  AND ds.time_range = '7d'
ORDER BY total_strength DESC;

-- ============================================================================
-- STEP 4: CHECK LEADERBOARD RANKINGS
-- ============================================================================

SELECT 
  '=== LEADERBOARD RANKINGS (7d) ===' as section;

-- T-Domain Leaderboard (Behavioral - should reflect play counts)
SELECT 
  ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as rank,
  artist_name,
  ROUND(domain_strength, 2) as t_strength,
  last_updated
FROM coliseum_leaderboard_t_7d
WHERE artist_name LIKE 'Test Artist%'
ORDER BY domain_strength DESC;

-- Composite Leaderboard (Overall ranking)
SELECT 
  ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as rank,
  artist_name,
  ROUND(domain_strength, 2) as composite_strength,
  last_updated
FROM coliseum_leaderboard_composite_7d
WHERE artist_name LIKE 'Test Artist%'
ORDER BY domain_strength DESC;

-- ============================================================================
-- STEP 5: EXPECTED VS ACTUAL RANKINGS
-- ============================================================================

SELECT 
  '=== EXPECTED VS ACTUAL RANKINGS ===' as section;

WITH expected_rankings AS (
  SELECT 
    ap.artist_name,
    COUNT(*) as expected_play_count,
    CASE 
      WHEN ap.artist_name = 'Test Artist Gamma' THEN 1
      WHEN ap.artist_name = 'Test Artist Alpha' THEN 2
      WHEN ap.artist_name = 'Test Artist Delta' THEN 3
      WHEN ap.artist_name = 'Test Artist Beta' THEN 4
    END as expected_rank
  FROM passport_entries pe
  JOIN artist_profiles ap ON ap.id = pe.entity_id
  WHERE pe.event_type = 'player.track_played'
    AND pe.created_at > NOW() - INTERVAL '2 days'
    AND ap.artist_name LIKE 'Test Artist%'
  GROUP BY ap.id, ap.artist_name
),
actual_rankings AS (
  SELECT 
    artist_name,
    ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as actual_rank,
    domain_strength
  FROM coliseum_leaderboard_t_7d
  WHERE artist_name LIKE 'Test Artist%'
)
SELECT 
  er.artist_name,
  er.expected_play_count,
  er.expected_rank,
  ar.actual_rank,
  ROUND(ar.domain_strength, 2) as actual_strength,
  CASE 
    WHEN er.expected_rank = ar.actual_rank THEN '✅ Match'
    ELSE '⚠️ Mismatch'
  END as status
FROM expected_rankings er
LEFT JOIN actual_rankings ar ON ar.artist_name = er.artist_name
ORDER BY er.expected_rank;

-- ============================================================================
-- STEP 6: WEIGHT ANALYSIS
-- ============================================================================

SELECT 
  '=== WEIGHT ANALYSIS ===' as section;

-- Check if weights are being applied correctly
SELECT 
  ap.artist_name,
  COUNT(*) as play_count,
  ROUND(AVG(cm.weight), 2) as avg_weight,
  ROUND(SUM(cm.effective_delta), 2) as total_effective_delta,
  ROUND(SUM(cm.delta), 2) as total_delta,
  ROUND(SUM(cm.effective_delta) / NULLIF(SUM(cm.delta), 0), 2) as weight_multiplier
FROM coliseum_dna_mutations cm
JOIN artist_profiles ap ON ap.id = cm.artist_id
WHERE ap.artist_name LIKE 'Test Artist%'
  AND cm.domain = 'T'  -- T-domain (behavioral/engagement)
GROUP BY ap.id, ap.artist_name
ORDER BY total_effective_delta DESC;

-- Check for weighted events (repeat plays, high completion)
SELECT 
  'Weighted Events' as check_type,
  COUNT(*) FILTER (WHERE (metadata->>'is_repeat_play')::boolean = true) as repeat_plays,
  COUNT(*) FILTER (WHERE (metadata->>'progress_percentage')::numeric > 80) as high_completion_plays,
  COUNT(*) FILTER (WHERE (metadata->>'progress_percentage')::numeric <= 30) as low_completion_plays
FROM passport_entries
WHERE event_type = 'player.track_played'
  AND entity_id IN (
    SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
  );

-- ============================================================================
-- SUMMARY
-- ============================================================================

SELECT 
  '=== SUMMARY ===' as section;

SELECT 
  'Test Artists' as metric,
  COUNT(*)::text as value
FROM artist_profiles
WHERE artist_name LIKE 'Test Artist%'

UNION ALL

SELECT 
  'Test Tracks' as metric,
  COUNT(*)::text as value
FROM content_items
WHERE title LIKE '%Track%'
  AND (title LIKE 'Alpha%' OR title LIKE 'Beta%' OR title LIKE 'Gamma%' OR title LIKE 'Delta%')

UNION ALL

SELECT 
  'Passport Events' as metric,
  COUNT(*)::text as value
FROM passport_entries
WHERE event_type = 'player.track_played'
  AND entity_id IN (
    SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
  )

UNION ALL

SELECT 
  'Mutations Created' as metric,
  COUNT(*)::text as value
FROM coliseum_dna_mutations
WHERE artist_id IN (
  SELECT id FROM artist_profiles WHERE artist_name LIKE 'Test Artist%'
)

UNION ALL

SELECT 
  'Artists in Leaderboard' as metric,
  COUNT(*)::text as value
FROM coliseum_leaderboard_t_7d
WHERE artist_name LIKE 'Test Artist%';
