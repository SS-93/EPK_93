-- Add role column to media_ids table and fix auth trigger
-- This makes media_ids consistent with the multi-role MediaID system

-- Step 1: Add role column to media_ids if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name='media_ids' AND column_name='role') THEN
        ALTER TABLE media_ids
        ADD COLUMN role user_role NOT NULL DEFAULT 'fan',
        ADD COLUMN version INTEGER DEFAULT 1,
        ADD COLUMN is_active BOOLEAN DEFAULT true;
    END IF;
END $$;

-- Step 2: Create or replace the handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- Create profile
  INSERT INTO public.profiles (id, display_name, role, email_verified, onboarding_completed)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'fan'),
    NEW.email_confirmed_at IS NOT NULL,
    false
  )
  ON CONFLICT (id) DO NOTHING;

  -- Create MediaID with role field
  INSERT INTO public.media_ids (user_uuid, role, interests, genre_preferences, privacy_settings, version, is_active)
  VALUES (
    NEW.id,
    COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'fan'),
    '{}',
    '{}',
    jsonb_build_object(
      'data_sharing', true,
      'location_access', false,
      'audio_capture', false,
      'anonymous_logging', true,
      'marketing_communications', false
    ),
    1,
    true
  )
  ON CONFLICT (user_uuid) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail signup
    RAISE WARNING 'Error in handle_new_user for %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Create the trigger (drop first if exists)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 4: Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON public.profiles TO authenticated;
GRANT ALL ON public.media_ids TO authenticated;
GRANT SELECT ON public.profiles TO anon;
GRANT SELECT ON public.media_ids TO anon;