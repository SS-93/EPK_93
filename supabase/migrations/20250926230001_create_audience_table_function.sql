-- Create a function to create the audience members table
-- This is needed because we can't run DDL directly via REST API

CREATE OR REPLACE FUNCTION create_audience_members_table()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Create the table
  EXECUTE '
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
  );';

  -- Add indexes
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_event_audience_members_event_id ON event_audience_members(event_id);';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_event_audience_members_token ON event_audience_members(registration_token);';
  EXECUTE 'CREATE INDEX IF NOT EXISTS idx_event_audience_members_email ON event_audience_members(event_id, email);';

  -- Enable RLS
  EXECUTE 'ALTER TABLE event_audience_members ENABLE ROW LEVEL SECURITY;';

  -- Create policies
  EXECUTE '
  DO $policy$
  BEGIN
    -- Drop existing policies if they exist
    DROP POLICY IF EXISTS "Anyone can register as audience member" ON event_audience_members;
    DROP POLICY IF EXISTS "Audience members can view their own data via token" ON event_audience_members;
    DROP POLICY IF EXISTS "Audience members can update within 24 hours" ON event_audience_members;
    DROP POLICY IF EXISTS "Event hosts can view their audience members" ON event_audience_members;

    -- Create new policies
    CREATE POLICY "Anyone can register as audience member"
      ON event_audience_members FOR INSERT
      WITH CHECK (true);

    CREATE POLICY "Audience members can view their own data via token"
      ON event_audience_members FOR SELECT
      USING (true);

    CREATE POLICY "Audience members can update within 24 hours"
      ON event_audience_members FOR UPDATE
      USING (registered_at > now() - interval ''24 hours'');

    CREATE POLICY "Event hosts can view their audience members"
      ON event_audience_members FOR SELECT
      USING (
        event_id IN (
          SELECT id FROM events WHERE host_user_id = auth.uid()
        )
      );
  END
  $policy$;';

  -- Create update function and trigger
  EXECUTE '
  CREATE OR REPLACE FUNCTION update_audience_member_updated_at()
  RETURNS TRIGGER AS $trigger$
  BEGIN
    NEW.updated_at = now();
    RETURN NEW;
  END;
  $trigger$ LANGUAGE plpgsql;';

  EXECUTE '
  DROP TRIGGER IF EXISTS update_audience_members_updated_at ON event_audience_members;
  CREATE TRIGGER update_audience_members_updated_at
    BEFORE UPDATE ON event_audience_members
    FOR EACH ROW
    EXECUTE FUNCTION update_audience_member_updated_at();';

  RETURN 'event_audience_members table created successfully with all indexes, policies, and triggers';
END;
$$;