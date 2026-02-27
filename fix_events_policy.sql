-- Drop and recreate the policy safely
DROP POLICY IF EXISTS "Public events are viewable by anyone" ON events;

CREATE POLICY "Public events are viewable by anyone"
  ON events FOR SELECT
  USING (status IN ('published', 'live', 'completed'));
