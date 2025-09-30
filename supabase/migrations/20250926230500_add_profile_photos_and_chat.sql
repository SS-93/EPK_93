-- Add profile photo fields to existing tables
-- Enable circular profile photos and prep for discussion rooms

-- Add profile image URL to event_artist_prospects
ALTER TABLE event_artist_prospects
ADD COLUMN IF NOT EXISTS profile_image_url TEXT;

-- Add profile image URL to event_audience_members
ALTER TABLE event_audience_members
ADD COLUMN IF NOT EXISTS profile_image_url TEXT;

-- Create event discussion rooms table (Twitch-style chat)
CREATE TABLE IF NOT EXISTS event_discussion_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  name TEXT NOT NULL DEFAULT 'General Chat',
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  max_participants INTEGER DEFAULT 500,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create chat messages table
CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES event_discussion_rooms(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,

  -- User identification (can be artist, audience, or host)
  user_id UUID, -- References auth.users for authenticated users
  user_name TEXT NOT NULL,
  user_type VARCHAR(20) CHECK (user_type IN ('artist', 'audience', 'host', 'anonymous')) NOT NULL,
  user_avatar_url TEXT,

  -- Message content
  message_text TEXT NOT NULL,
  message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text', 'emoji', 'system', 'vote_notification')),

  -- Metadata
  reply_to_message_id UUID REFERENCES chat_messages(id),
  is_deleted BOOLEAN DEFAULT false,
  is_pinned BOOLEAN DEFAULT false,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create chat reactions table (like Twitch emotes)
CREATE TABLE IF NOT EXISTS chat_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id UUID, -- Can be null for anonymous reactions
  user_name TEXT NOT NULL,
  reaction_type VARCHAR(50) NOT NULL, -- emoji, custom_emote, etc.
  reaction_value TEXT NOT NULL, -- actual emoji or emote code
  created_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(message_id, user_name, reaction_value)
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_event_discussion_rooms_event_id ON event_discussion_rooms(event_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_room_id ON chat_messages(room_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_event_id ON chat_messages(event_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON chat_messages(created_at);
CREATE INDEX IF NOT EXISTS idx_chat_reactions_message_id ON chat_reactions(message_id);

-- RLS policies for discussion rooms
ALTER TABLE event_discussion_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_reactions ENABLE ROW LEVEL SECURITY;

-- Discussion rooms policies
CREATE POLICY "Anyone can view active discussion rooms"
  ON event_discussion_rooms FOR SELECT
  USING (is_active = true);

CREATE POLICY "Event hosts can manage discussion rooms"
  ON event_discussion_rooms FOR ALL
  USING (
    event_id IN (
      SELECT id FROM events WHERE host_user_id = auth.uid()
    )
  );

-- Chat messages policies
CREATE POLICY "Anyone can view chat messages in active rooms"
  ON chat_messages FOR SELECT
  USING (
    room_id IN (
      SELECT id FROM event_discussion_rooms WHERE is_active = true
    )
  );

CREATE POLICY "Authenticated users can send messages"
  ON chat_messages FOR INSERT
  WITH CHECK (
    room_id IN (
      SELECT id FROM event_discussion_rooms WHERE is_active = true
    )
  );

CREATE POLICY "Users can update their own messages"
  ON chat_messages FOR UPDATE
  USING (user_id = auth.uid() OR user_name = current_setting('app.current_user_name', true));

-- Chat reactions policies
CREATE POLICY "Anyone can view reactions"
  ON chat_reactions FOR SELECT
  USING (true);

CREATE POLICY "Anyone can add reactions"
  ON chat_reactions FOR INSERT
  WITH CHECK (true);

-- Functions for chat functionality

-- Function to create default discussion room for new events
CREATE OR REPLACE FUNCTION create_default_discussion_room()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO event_discussion_rooms (event_id, name, description)
  VALUES (NEW.id, 'General Chat', 'Main discussion room for ' || NEW.title);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-create discussion room
CREATE TRIGGER create_event_discussion_room
  AFTER INSERT ON events
  FOR EACH ROW
  EXECUTE FUNCTION create_default_discussion_room();

-- Function to send system messages
CREATE OR REPLACE FUNCTION send_system_message(
  p_room_id UUID,
  p_event_id UUID,
  p_message TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_message_id UUID;
BEGIN
  INSERT INTO chat_messages (
    room_id,
    event_id,
    user_id,
    user_name,
    user_type,
    message_text,
    message_type
  ) VALUES (
    p_room_id,
    p_event_id,
    null,
    'System',
    'system',
    p_message,
    'system'
  ) RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;

-- Function to notify chat when someone votes
CREATE OR REPLACE FUNCTION notify_chat_vote(
  p_event_id UUID,
  p_voter_name TEXT,
  p_artist_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_id UUID;
  v_message_id UUID;
BEGIN
  -- Get the default room for the event
  SELECT id INTO v_room_id
  FROM event_discussion_rooms
  WHERE event_id = p_event_id AND name = 'General Chat'
  LIMIT 1;

  IF v_room_id IS NOT NULL THEN
    INSERT INTO chat_messages (
      room_id,
      event_id,
      user_id,
      user_name,
      user_type,
      message_text,
      message_type
    ) VALUES (
      v_room_id,
      p_event_id,
      null,
      'System',
      'system',
      p_voter_name || ' voted for ' || p_artist_name || ' 🗳️',
      'vote_notification'
    ) RETURNING id INTO v_message_id;
  END IF;

  RETURN v_message_id;
END;
$$;

-- Update triggers for updated_at timestamps
CREATE OR REPLACE FUNCTION update_chat_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_discussion_rooms_updated_at
  BEFORE UPDATE ON event_discussion_rooms
  FOR EACH ROW
  EXECUTE FUNCTION update_chat_updated_at();

CREATE TRIGGER update_chat_messages_updated_at
  BEFORE UPDATE ON chat_messages
  FOR EACH ROW
  EXECUTE FUNCTION update_chat_updated_at();

-- Sample data for testing
DO $$
DECLARE
  v_event_id UUID;
  v_room_id UUID;
BEGIN
  -- Only add sample data if no discussion rooms exist
  IF NOT EXISTS (SELECT 1 FROM event_discussion_rooms LIMIT 1) THEN
    -- Get first event
    SELECT id INTO v_event_id FROM events ORDER BY created_at DESC LIMIT 1;

    IF v_event_id IS NOT NULL THEN
      INSERT INTO event_discussion_rooms (event_id, name, description)
      VALUES (v_event_id, 'General Chat', 'Main discussion room')
      RETURNING id INTO v_room_id;

      -- Add welcome message
      IF v_room_id IS NOT NULL THEN
        INSERT INTO chat_messages (room_id, event_id, user_id, user_name, user_type, message_text, message_type)
        VALUES (v_room_id, v_event_id, null, 'System', 'system', 'Welcome to the event chat! 🎵', 'system');
      END IF;
    END IF;
  END IF;
END $$;