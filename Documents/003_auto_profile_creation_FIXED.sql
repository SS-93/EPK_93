-- 003_auto_profile_creation.sql (FIXED)
-- Automatic profile and MediaID creation with proper role handling

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- Create profile
  INSERT INTO public.profiles (id, display_name, role, email_verified, onboarding_completed)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'fan')::user_role,
    NEW.email_confirmed_at IS NOT NULL,
    false
  );
  
  -- ✅ FIXED: Create MediaID with role field (required for new schema)
  INSERT INTO public.media_ids (user_uuid, role, interests, genre_preferences, privacy_settings, version, is_active)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'role', 'fan')::user_role,  -- ✅ Required role field
    '{}',
    '{}',
    '{
      "data_sharing": true,
      "location_access": false,
      "audio_capture": false,
      "anonymous_logging": true,
      "marketing_communications": false
    }'::jsonb,
    1,
    true
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();