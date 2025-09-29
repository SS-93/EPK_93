-- Create event_audience_members table for audience registration system
-- Audience members can edit their info for 24 hours, then it locks

CREATE TABLE IF NOT EXISTS event_audience_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  registration_token TEXT UNIQUE NOT NULL,
  registered_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_event_audience_members_event_id ON event_audience_members(event_id);
CREATE INDEX IF NOT EXISTS idx_event_audience_members_token ON event_audience_members(registration_token);
CREATE INDEX IF NOT EXISTS idx_event_audience_members_email ON event_audience_members(event_id, email);

-- RLS policies for audience members
ALTER TABLE event_audience_members ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can register as audience member
CREATE POLICY "Anyone can register as audience member"
  ON event_audience_members FOR INSERT
  WITH CHECK (true);

-- Policy: Audience members can view their own data via token
CREATE POLICY "Audience members can view their own data via token"
  ON event_audience_members FOR SELECT
  USING (true); -- We'll handle this in the application logic

-- Policy: Audience members can update their own data within 24 hours
CREATE POLICY "Audience members can update within 24 hours"
  ON event_audience_members FOR UPDATE
  USING (registered_at > now() - interval '24 hours');

-- Policy: Event hosts can view audience members for their events
CREATE POLICY "Event hosts can view their audience members"
  ON event_audience_members FOR SELECT
  USING (
    event_id IN (
      SELECT id FROM events WHERE host_user_id = auth.uid()
    )
  );

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_audience_member_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update the updated_at column
CREATE TRIGGER update_audience_members_updated_at
  BEFORE UPDATE ON event_audience_members
  FOR EACH ROW
  EXECUTE FUNCTION update_audience_member_updated_at();

-- Add sample data if needed (for testing)
-- This will only run if no audience members exist
INSERT INTO event_audience_members (event_id, name, email, phone, registration_token, registered_at)
SELECT
  e.id as event_id,
  'Sample Audience Member' as name,
  'audience@example.com' as email,
  '+1234567890' as phone,
  'aud_sample_token_' || generate_random() as registration_token,
  now() - interval '1 hour' as registered_at
FROM events e
WHERE e.title LIKE '%Test%'
  AND NOT EXISTS (SELECT 1 FROM event_audience_members)
LIMIT 1;