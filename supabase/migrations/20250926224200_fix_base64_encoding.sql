-- Fix base64url encoding issue in CRM functions
-- PostgreSQL doesn't support base64url encoding, use base64 instead

-- Update the add_artist_prospect_to_event function with proper base64 encoding
CREATE OR REPLACE FUNCTION add_artist_prospect_to_event(
  p_event_id UUID,
  p_artist_name TEXT,
  p_email TEXT DEFAULT NULL,
  p_instagram_handle TEXT DEFAULT NULL,
  p_bio TEXT DEFAULT NULL,
  p_host_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_prospect_id UUID;
  v_registration_token TEXT;
BEGIN
  -- Generate registration token using standard base64 encoding
  v_registration_token := 'reg_' || encode(gen_random_bytes(32), 'base64');
  -- Remove any problematic characters for URL safety
  v_registration_token := replace(replace(replace(v_registration_token, '+', 'X'), '/', 'Y'), '=', 'Z');

  -- Create artist prospect
  INSERT INTO event_artist_prospects (
    event_id,
    artist_name,
    email,
    instagram_handle,
    bio,
    host_notes,
    registration_token,
    contact_status,
    created_at
  ) VALUES (
    p_event_id,
    p_artist_name,
    p_email,
    p_instagram_handle,
    p_bio,
    p_host_notes,
    v_registration_token,
    'invited',
    now()
  ) RETURNING id INTO v_prospect_id;

  RETURN v_prospect_id;
END;
$$;

-- Also fix the auto-generate registration token trigger
CREATE OR REPLACE FUNCTION generate_registration_token()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.registration_token IS NULL THEN
    -- Use standard base64 encoding and make it URL-safe manually
    NEW.registration_token := 'reg_' || replace(replace(replace(encode(gen_random_bytes(32), 'base64'), '+', 'X'), '/', 'Y'), '=', 'Z');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;