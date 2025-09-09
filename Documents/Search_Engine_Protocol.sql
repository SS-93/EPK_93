-- ===============================================
-- SEARCH ENGINE PROTOCOL
-- ===============================================
-- Purpose: Denormalized search/index table for fast discovery, search, and listing
-- Scope: Published audio only; no file duplication. Works with either 'artists' or 'artist_profiles'.

-- 0) Extensions (safe)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

-- 1) Artist lookup view (supports dbs using either 'artists' or 'artist_profiles')
DO $$
BEGIN
  BEGIN
    EXECUTE 'CREATE OR REPLACE VIEW artist_lookup AS SELECT id, artist_name FROM artists';
  EXCEPTION WHEN undefined_table THEN
    EXECUTE 'CREATE OR REPLACE VIEW artist_lookup AS SELECT id, artist_name FROM artist_profiles';
  END;
END;
$$;

-- 2) Search index table (one row per published audio)
CREATE TABLE IF NOT EXISTS content_search_index (
  content_id UUID PRIMARY KEY REFERENCES content_items(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  artist_id UUID NOT NULL,
  artist_name TEXT NOT NULL,
  genre TEXT,
  tags TEXT[] DEFAULT '{}',
  mood_tags TEXT[] DEFAULT '{}',
  bpm DECIMAL, "key" TEXT, mode TEXT, energy DECIMAL, valence DECIMAL, danceability DECIMAL,
  created_at TIMESTAMP NOT NULL,
  search_vector tsvector
);

-- Ensure plain search_vector column (not generated) and prepare maintenance trigger
DROP INDEX IF EXISTS idx_csi_search_vector;
ALTER TABLE content_search_index DROP COLUMN IF EXISTS search_vector;
ALTER TABLE content_search_index ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Trigger function to maintain search_vector on INSERT/UPDATE
CREATE OR REPLACE FUNCTION trg_csi_search_vector_maintain()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('simple', coalesce(unaccent(NEW.title), '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(unaccent(NEW.artist_name), '')), 'A') ||
    setweight(to_tsvector('simple', array_to_string(coalesce(NEW.tags, '{}'), ' ')), 'B') ||
    setweight(to_tsvector('simple', array_to_string(coalesce(NEW.mood_tags, '{}'), ' ')), 'B');
  RETURN NEW;
END;
$$;

-- Trigger to call the maintenance function
DROP TRIGGER IF EXISTS csi_search_vector_maintain ON content_search_index;
CREATE TRIGGER csi_search_vector_maintain
BEFORE INSERT OR UPDATE OF title, artist_name, tags, mood_tags
ON content_search_index
FOR EACH ROW EXECUTE FUNCTION trg_csi_search_vector_maintain();

-- Backfill search_vector for existing rows (if any)
UPDATE content_search_index
SET search_vector =
  setweight(to_tsvector('simple', coalesce(unaccent(title), '')), 'A') ||
  setweight(to_tsvector('simple', coalesce(unaccent(artist_name), '')), 'A') ||
  setweight(to_tsvector('simple', array_to_string(coalesce(tags, '{}'), ' ')), 'B') ||
  setweight(to_tsvector('simple', array_to_string(coalesce(mood_tags, '{}'), ' ')), 'B')
WHERE search_vector IS NULL;

-- 3) Backfill from current data (published audio only)
INSERT INTO content_search_index (content_id, title, artist_id, artist_name, genre, tags, mood_tags,
                                  bpm, "key", mode, energy, valence, danceability, created_at)
SELECT
  ci.id,
  ci.title,
  ci.artist_id,
  al.artist_name,
  ci.metadata->>'genre' AS genre,
  COALESCE(ARRAY(SELECT jsonb_array_elements_text(ci.metadata->'tags')), '{}')::text[] AS tags,
  COALESCE(mt.tags, '{}') AS mood_tags,
  af.bpm, af.key, af.mode, af.energy, af.valence, af.danceability,
  ci.created_at
FROM content_items ci
JOIN artist_lookup al ON al.id = ci.artist_id
LEFT JOIN audio_features af ON af.content_id = ci.id
LEFT JOIN mood_tags mt ON mt.content_id = ci.id
WHERE ci.content_type = 'audio' AND ci.is_published = true
ON CONFLICT (content_id) DO NOTHING;

-- 4) Indexes
CREATE INDEX IF NOT EXISTS idx_csi_search_vector ON content_search_index USING GIN (search_vector);
CREATE INDEX IF NOT EXISTS idx_csi_tags ON content_search_index USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_csi_mood_tags ON content_search_index USING GIN (mood_tags);
CREATE INDEX IF NOT EXISTS idx_csi_title_trgm ON content_search_index USING GIN (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_csi_artist_trgm ON content_search_index USING GIN (artist_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_csi_created_at ON content_search_index (created_at DESC);

-- 5) Upsert/maintenance function (idempotent)
CREATE OR REPLACE FUNCTION upsert_content_search_index(p_content_id UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO content_search_index (content_id, title, artist_id, artist_name, genre, tags, mood_tags,
                                    bpm, "key", mode, energy, valence, danceability, created_at)
  SELECT
    ci.id, ci.title, ci.artist_id, al.artist_name,
    ci.metadata->>'genre',
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(ci.metadata->'tags')), '{}')::text[],
    COALESCE(mt.tags, '{}'),
    af.bpm, af.key, af.mode, af.energy, af.valence, af.danceability,
    ci.created_at
  FROM content_items ci
  JOIN artist_lookup al ON al.id = ci.artist_id
  LEFT JOIN audio_features af ON af.content_id = ci.id
  LEFT JOIN mood_tags mt ON mt.content_id = ci.id
  WHERE ci.id = p_content_id AND ci.content_type = 'audio' AND ci.is_published = true
  ON CONFLICT (content_id) DO UPDATE SET
    title = EXCLUDED.title,
    artist_id = EXCLUDED.artist_id,
    artist_name = EXCLUDED.artist_name,
    genre = EXCLUDED.genre,
    tags = EXCLUDED.tags,
    mood_tags = EXCLUDED.mood_tags,
    bpm = EXCLUDED.bpm,
    "key" = EXCLUDED."key",
    mode = EXCLUDED.mode,
    energy = EXCLUDED.energy,
    valence = EXCLUDED.valence,
    danceability = EXCLUDED.danceability,
    created_at = EXCLUDED.created_at;

  -- If now unpublished, remove from index
  IF NOT EXISTS (
    SELECT 1 FROM content_items WHERE id = p_content_id AND content_type = 'audio' AND is_published = true
  ) THEN
    DELETE FROM content_search_index WHERE content_id = p_content_id;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- 6) Triggers (content, mood tags, audio features) - artist name sync supports either table
CREATE OR REPLACE FUNCTION trg_touch_csi_content_items() RETURNS TRIGGER AS $$
BEGIN
  PERFORM upsert_content_search_index(COALESCE(NEW.id, OLD.id));
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_touch_csi_mood_tags() RETURNS TRIGGER AS $$
BEGIN
  PERFORM upsert_content_search_index(NEW.content_id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_touch_csi_audio_features() RETURNS TRIGGER AS $$
BEGIN
  PERFORM upsert_content_search_index(NEW.content_id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_touch_csi_artists_name() RETURNS TRIGGER AS $$
BEGIN
  UPDATE content_search_index csi
  SET artist_name = NEW.artist_name
  WHERE csi.artist_id = NEW.id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS csi_on_content_items ON content_items;
CREATE TRIGGER csi_on_content_items AFTER INSERT OR UPDATE OF title, metadata, is_published, artist_id ON content_items
FOR EACH ROW EXECUTE FUNCTION trg_touch_csi_content_items();

DROP TRIGGER IF EXISTS csi_on_mood_tags ON mood_tags;
CREATE TRIGGER csi_on_mood_tags AFTER INSERT OR UPDATE ON mood_tags
FOR EACH ROW EXECUTE FUNCTION trg_touch_csi_mood_tags();

DROP TRIGGER IF EXISTS csi_on_audio_features ON audio_features;
CREATE TRIGGER csi_on_audio_features AFTER INSERT OR UPDATE ON audio_features
FOR EACH ROW EXECUTE FUNCTION trg_touch_csi_audio_features();

-- Create artist name trigger on whichever table exists
DO $$
BEGIN
  BEGIN
    DROP TRIGGER IF EXISTS csi_on_artists ON artists;
    CREATE TRIGGER csi_on_artists AFTER UPDATE OF artist_name ON artists
    FOR EACH ROW EXECUTE FUNCTION trg_touch_csi_artists_name();
  EXCEPTION WHEN undefined_table THEN
    DROP TRIGGER IF EXISTS csi_on_artist_profiles ON artist_profiles;
    CREATE TRIGGER csi_on_artist_profiles AFTER UPDATE OF artist_name ON artist_profiles
    FOR EACH ROW EXECUTE FUNCTION trg_touch_csi_artists_name();
  END;
END;
$$;

-- 7) RLS: enable public reads of the search index (metadata only)
ALTER TABLE content_search_index ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can search published index" ON content_search_index;
CREATE POLICY "Public can search published index" ON content_search_index
  FOR SELECT TO public USING (true);

-- 8) Search RPCs
CREATE OR REPLACE FUNCTION search_content_index(q TEXT, genres TEXT[] DEFAULT NULL, moods TEXT[] DEFAULT NULL, limit_rows INT DEFAULT 50)
RETURNS TABLE (
  content_id UUID,
  title TEXT,
  artist_id UUID,
  artist_name TEXT,
  genre TEXT,
  mood_tags TEXT[],
  created_at TIMESTAMP
) AS $$
BEGIN
  RETURN QUERY
  SELECT csi.content_id, csi.title, csi.artist_id, csi.artist_name, csi.genre, csi.mood_tags, csi.created_at
  FROM content_search_index csi
  WHERE (q IS NULL OR csi.search_vector @@ plainto_tsquery('simple', unaccent(q)))
    AND (genres IS NULL OR csi.genre = ANY(genres))
    AND (moods IS NULL OR csi.mood_tags && moods)
  ORDER BY csi.created_at DESC
  LIMIT limit_rows;
END;
$$ LANGUAGE plpgsql STABLE;

REVOKE ALL ON FUNCTION search_content_index(TEXT, TEXT[], TEXT[], INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION search_content_index(TEXT, TEXT[], TEXT[], INT) TO anon, authenticated;

-- ===============================================
-- END SEARCH ENGINE PROTOCOL
-- ===============================================


