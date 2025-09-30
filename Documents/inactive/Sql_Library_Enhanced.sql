-- ===============================================
-- BUCKET & MEDIAID - ENHANCED 2 LIBRARY v2.0
-- ===============================================
-- Complete database setup with Audio Intelligence features
-- Deploy scripts in order: 001 → 009 (new sections added)
-- 
-- PHASE 1 ENHANCEMENTS:
-- - Audio intelligence tables (audio_features, mood_tags, lyrics)
-- - Processing job queue system
-- - Enhanced content_items table
-- - Storage bucket fixes

-- ===============================================
-- SCRIPT 001: CORE SCHEMA (FIXED)
-- ===============================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ✅ FIXED: Handle existing enum types
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('fan', 'artist', 'brand', 'admin', 'developer');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE subscription_status AS ENUM ('active', 'canceled', 'paused', 'expired');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE content_type AS ENUM ('audio', 'video', 'image', 'document');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE campaign_status AS ENUM ('draft', 'active', 'paused', 'completed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 🎵 NEW: Job status enum for audio processing
DO $$ BEGIN
    CREATE TYPE job_status AS ENUM ('queued', 'running', 'completed', 'failed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 🎵 NEW: Job type enum for audio processing
DO $$ BEGIN
    CREATE TYPE job_type AS ENUM ('audio_features', 'mood_analysis', 'lyric_extraction');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create tables with IF NOT EXISTS
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_url TEXT,
  role user_role NOT NULL DEFAULT 'fan',
  email_verified BOOLEAN DEFAULT FALSE,
  onboarding_completed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- MediaID Table with multi-role support (handle existing table)
CREATE TABLE IF NOT EXISTS media_ids (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uuid UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  interests TEXT[] DEFAULT '{}',
  genre_preferences TEXT[] DEFAULT '{}',
  content_flags JSONB DEFAULT '{}',
  location_code TEXT,
  profile_embedding VECTOR(1536),
  privacy_settings JSONB DEFAULT '{
    "data_sharing": true,
    "location_access": false,
    "audio_capture": false,
    "anonymous_logging": true,
    "marketing_communications": false
  }',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- ✅ FIXED: Add missing columns for existing media_ids table
ALTER TABLE media_ids 
ADD COLUMN IF NOT EXISTS role user_role NOT NULL DEFAULT 'fan',
ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1,
ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;
-- placement note: satisfies RLS updates that check is_active; no separate migration needed if this library is primary

-- Drop old constraint if exists
ALTER TABLE media_ids DROP CONSTRAINT IF EXISTS media_ids_user_uuid_key;

-- Add new constraint if not exists
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'media_ids_user_role_unique'
  ) THEN
    ALTER TABLE media_ids ADD CONSTRAINT media_ids_user_role_unique 
    UNIQUE (user_uuid, role);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS artists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  artist_name TEXT NOT NULL,
  bio TEXT,
  banner_url TEXT,
  social_links JSONB DEFAULT '{}',
  verification_status TEXT DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS brands (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  brand_name TEXT NOT NULL,
  description TEXT,
  website_url TEXT,
  logo_url TEXT,
  industry TEXT,
  contact_email TEXT,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fan_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  artist_id UUID REFERENCES artists(id) ON DELETE CASCADE,
  tier TEXT NOT NULL,
  price_cents INTEGER NOT NULL,
  status subscription_status DEFAULT 'active',
  stripe_subscription_id TEXT UNIQUE,
  current_period_start TIMESTAMP,
  current_period_end TIMESTAMP,
  cancel_at_period_end BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(fan_id, artist_id)
);
-- placement note: ensure webhook handlers persist price_cents; otherwise add a follow-up migration to drop NOT NULL

CREATE TABLE IF NOT EXISTS content_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id UUID REFERENCES artists(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  content_type content_type NOT NULL,
  file_path TEXT NOT NULL,
  file_size_bytes BIGINT,
  duration_seconds INTEGER,
  unlock_date TIMESTAMP,
  milestone_condition JSONB,
  is_premium BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- ✅ FIXED: Add missing columns for content_items
ALTER TABLE content_items 
ADD COLUMN IF NOT EXISTS scheduled_unlock_job_id TEXT,
ADD COLUMN IF NOT EXISTS auto_unlock_enabled BOOLEAN DEFAULT TRUE;

-- 🎵 NEW: Enhanced columns for Phase 1 audio intelligence
ALTER TABLE content_items 
ADD COLUMN IF NOT EXISTS audio_checksum TEXT,
ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending',
ADD COLUMN IF NOT EXISTS file_type TEXT,
ADD COLUMN IF NOT EXISTS duration_ms INTEGER,
ADD COLUMN IF NOT EXISTS waveform_peaks JSONB;

CREATE TABLE IF NOT EXISTS campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id UUID REFERENCES brands(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  targeting_criteria JSONB NOT NULL,
  budget_cents INTEGER NOT NULL,
  payment_model TEXT NOT NULL,
  status campaign_status DEFAULT 'draft',
  start_date TIMESTAMP,
  end_date TIMESTAMP,
  assets JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- ✅ FIXED: Add missing columns for campaigns
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS total_impressions INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_clicks INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS total_conversions INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS spend_cents INTEGER DEFAULT 0;

-- ✅ FIXED: Create campaign_placements table
CREATE TABLE IF NOT EXISTS campaign_placements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id UUID REFERENCES campaigns(id) ON DELETE CASCADE,
  artist_id UUID REFERENCES artists(id) ON DELETE CASCADE,
  placement_fee_cents INTEGER NOT NULL,
  status TEXT DEFAULT 'pending',
  metrics JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(campaign_id, artist_id)
);

CREATE TABLE IF NOT EXISTS media_engagement_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  content_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  session_id TEXT,
  user_agent TEXT,
  ip_address INET,
  is_anonymous BOOLEAN DEFAULT TRUE,
  metadata JSONB DEFAULT '{}',
  timestamp TIMESTAMP DEFAULT now()
);

CREATE TABLE IF NOT EXISTS transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  amount_cents INTEGER NOT NULL,
  currency TEXT DEFAULT 'USD',
  transaction_type TEXT NOT NULL,
  status TEXT DEFAULT 'pending',
  stripe_payment_intent_id TEXT,
  description TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- ===============================================
-- SCRIPT 009: AUDIO INTELLIGENCE TABLES (NEW)
-- ===============================================
-- 🎵 NEW: Audio intelligence and processing tables for Phase 1

-- Audio features extracted from tracks
CREATE TABLE IF NOT EXISTS audio_features (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  bpm DECIMAL,
  key TEXT,
  mode TEXT CHECK (mode IN ('major', 'minor')),
  energy DECIMAL CHECK (energy >= 0 AND energy <= 1),
  valence DECIMAL CHECK (valence >= 0 AND valence <= 1),
  danceability DECIMAL CHECK (danceability >= 0 AND danceability <= 1),
  loudness DECIMAL,
  confidence DECIMAL CHECK (confidence >= 0 AND confidence <= 1),
  source TEXT NOT NULL, -- 'tunebat', 'spotify', 'essentia', etc.
  raw_analysis JSONB, -- Store full API response for debugging
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(content_id) -- One audio feature set per content item
);

-- Mood tags derived from audio features and other signals
CREATE TABLE IF NOT EXISTS mood_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  tags TEXT[] NOT NULL,
  confidence DECIMAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  derived_from JSONB DEFAULT '{"audio": false, "lyrics": false, "engagement": false}',
  rationale TEXT[], -- Human-readable explanations for tag assignments
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(content_id) -- One mood tag set per content item
);

-- Lyrics data with sync information
CREATE TABLE IF NOT EXISTS lyrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  source TEXT NOT NULL, -- 'artist_provided', 'musixmatch', 'genius', 'forced_alignment'
  is_synced BOOLEAN DEFAULT false,
  language TEXT DEFAULT 'en',
  text TEXT, -- Full lyric text
  segments JSONB, -- Array of {tStartMs, tEndMs, line, words?}
  rights JSONB, -- {owner, license, usage_terms}
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE(content_id) -- One lyric set per content item
);

-- Processing job queue for async audio analysis
CREATE TABLE IF NOT EXISTS audio_processing_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  job_type job_type NOT NULL,
  status job_status DEFAULT 'queued',
  provider TEXT, -- Which service is processing (tunebat, spotify, etc.)
  attempts INTEGER DEFAULT 0,
  max_attempts INTEGER DEFAULT 3,
  error_message TEXT,
  result JSONB, -- Store processing results
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  scheduled_at TIMESTAMP DEFAULT now(),
  started_at TIMESTAMP,
  completed_at TIMESTAMP
);

-- Essential indexes (non-concurrent for transaction safety)
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
CREATE INDEX IF NOT EXISTS idx_media_ids_user_role_active ON media_ids(user_uuid, role, is_active);
CREATE INDEX IF NOT EXISTS idx_media_ids_interests ON media_ids USING GIN(interests);
CREATE INDEX IF NOT EXISTS idx_subscriptions_fan_artist ON subscriptions(fan_id, artist_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_content_items_artist ON content_items(artist_id);
CREATE INDEX IF NOT EXISTS idx_content_items_unlock_date ON content_items(unlock_date);
CREATE INDEX IF NOT EXISTS idx_campaigns_brand ON campaigns(brand_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);
CREATE INDEX IF NOT EXISTS idx_campaign_placements_campaign ON campaign_placements(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_placements_artist ON campaign_placements(artist_id);
CREATE INDEX IF NOT EXISTS idx_engagement_log_content_timestamp ON media_engagement_log(content_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);

-- 🎵 NEW: Audio intelligence indexes
CREATE INDEX IF NOT EXISTS idx_audio_features_content_id ON audio_features(content_id);
CREATE INDEX IF NOT EXISTS idx_audio_features_bpm ON audio_features(bpm) WHERE bpm IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audio_features_key ON audio_features(key) WHERE key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audio_features_energy ON audio_features(energy) WHERE energy IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_mood_tags_content_id ON mood_tags(content_id);
CREATE INDEX IF NOT EXISTS idx_mood_tags_tags ON mood_tags USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_lyrics_content_id ON lyrics(content_id);
CREATE INDEX IF NOT EXISTS idx_lyrics_synced ON lyrics(is_synced) WHERE is_synced = true;
CREATE INDEX IF NOT EXISTS idx_audio_processing_jobs_status ON audio_processing_jobs(status);
CREATE INDEX IF NOT EXISTS idx_audio_processing_jobs_type_status ON audio_processing_jobs(job_type, status);
CREATE INDEX IF NOT EXISTS idx_audio_processing_jobs_scheduled ON audio_processing_jobs(scheduled_at) WHERE status = 'queued';
CREATE INDEX IF NOT EXISTS idx_content_items_checksum ON content_items(audio_checksum) WHERE audio_checksum IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_content_items_processing_status ON content_items(processing_status);

-- ===============================================
-- SCRIPT 002: STORAGE BUCKETS & POLICIES
-- ===============================================

-- Create storage buckets
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  ('artist-content', 'artist-content', false, 52428800, ARRAY['audio/*', 'video/*', 'image/*']),
  ('brand-assets', 'brand-assets', false, 10485760, ARRAY['image/*', 'video/*']),
  ('temp-uploads', 'temp-uploads', false, 104857600, ARRAY['audio/*', 'video/*', 'image/*']),
  ('public-assets', 'public-assets', true, 5242880, ARRAY['image/*']),
  ('profile-avatars', 'profile-avatars', false, 2097152, ARRAY['image/*']),
  ('media-uploads', 'media-uploads', false, 52428800, ARRAY['audio/*', 'video/*', 'image/*'])
ON CONFLICT (id) DO NOTHING;

-- 🎵 UPDATED: Fixed bucket name for artist content policies
DROP POLICY IF EXISTS "Artists can upload their own content" ON storage.objects;
CREATE POLICY "Artists can upload their own content" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'artist-content' 
    AND auth.uid()::text = (storage.foldername(name))[1]
    AND EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'artist')
  );

DROP POLICY IF EXISTS "Artists can manage their own content" ON storage.objects;
CREATE POLICY "Artists can manage their own content" ON storage.objects
  FOR ALL USING (
    bucket_id = 'artist-content' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "Subscribers can view artist content" ON storage.objects;
CREATE POLICY "Subscribers can view artist content" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'artist-content'
    AND EXISTS(
      SELECT 1 FROM subscriptions s
      JOIN artists a ON s.artist_id = a.id
      WHERE s.fan_id = auth.uid()
      AND a.user_id::text = (storage.foldername(name))[1]
      AND s.status = 'active'
    )
  );

-- Brand assets policies
DROP POLICY IF EXISTS "Brands can upload their own assets" ON storage.objects;
CREATE POLICY "Brands can upload their own assets" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'brand-assets' 
    AND auth.uid()::text = (storage.foldername(name))[1]
    AND EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'brand')
  );

DROP POLICY IF EXISTS "Brands can manage their own assets" ON storage.objects;
CREATE POLICY "Brands can manage their own assets" ON storage.objects
  FOR ALL USING (
    bucket_id = 'brand-assets' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Profile avatar policies
DROP POLICY IF EXISTS "Users can manage their own avatar" ON storage.objects;
CREATE POLICY "Users can manage their own avatar" ON storage.objects
  FOR ALL USING (
    bucket_id = 'profile-avatars' 
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Public assets policies
DROP POLICY IF EXISTS "Anyone can view public assets" ON storage.objects;
CREATE POLICY "Anyone can view public assets" ON storage.objects
  FOR SELECT USING (bucket_id = 'public-assets');

DROP POLICY IF EXISTS "Authenticated users can upload public assets" ON storage.objects;
CREATE POLICY "Authenticated users can upload public assets" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'public-assets' 
    AND auth.role() = 'authenticated'
  );

-- ===============================================
-- SCRIPT 003: AUTO-PROFILE CREATION (FIXED)
-- ===============================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- Create profile
  INSERT INTO public.profiles (id, display_name, role, email_verified, onboarding_completed)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'fan')::public.user_role,  -- ✅ FIXED
    NEW.email_confirmed_at IS NOT NULL,
    false
  );
  
  -- Create MediaID entry  
  INSERT INTO public.media_ids (user_uuid, role, interests, genre_preferences, privacy_settings, version, is_active)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'role', 'fan')::public.user_role,  -- ✅ FIXED  
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

-- ===============================================
-- SCRIPT 004: ROW LEVEL SECURITY (FIXED)
-- ===============================================

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_ids ENABLE ROW LEVEL SECURITY;
ALTER TABLE artists ENABLE ROW LEVEL SECURITY;
ALTER TABLE brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_engagement_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- 🎵 NEW: Enable RLS on audio intelligence tables
ALTER TABLE audio_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE mood_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE lyrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE audio_processing_jobs ENABLE ROW LEVEL SECURITY;

-- ✅ FIXED: Only enable RLS on campaign_placements if it exists
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'campaign_placements') THEN
    ALTER TABLE campaign_placements ENABLE ROW LEVEL SECURITY;
  END IF;
END $$;

-- Drop existing policies safely
DROP POLICY IF EXISTS "Users can view their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Public can view artist profiles" ON profiles;

-- Profiles policies
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert their own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Public can view artist profiles" ON profiles
  FOR SELECT USING (role = 'artist');

-- MediaID policies (drop and recreate)
DROP POLICY IF EXISTS "Users can view their own MediaID records" ON media_ids;
DROP POLICY IF EXISTS "Users can update their own MediaID records" ON media_ids;
DROP POLICY IF EXISTS "Users can insert new MediaID records" ON media_ids;
DROP POLICY IF EXISTS "Users can delete their own MediaID records" ON media_ids;

CREATE POLICY "Users can view their own MediaID records" ON media_ids
  FOR SELECT USING (auth.uid() = user_uuid);
CREATE POLICY "Users can update their own MediaID records" ON media_ids
  FOR UPDATE USING (auth.uid() = user_uuid);
CREATE POLICY "Users can insert new MediaID records" ON media_ids
  FOR INSERT WITH CHECK (auth.uid() = user_uuid);
CREATE POLICY "Users can delete their own MediaID records" ON media_ids
  FOR DELETE USING (auth.uid() = user_uuid);

-- Artists policies
DROP POLICY IF EXISTS "Artists can manage their own data" ON artists;
DROP POLICY IF EXISTS "Public can view artist profiles" ON artists;

CREATE POLICY "Artists can manage their own data" ON artists
  FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Public can view artist profiles" ON artists
  FOR SELECT USING (true);

-- Brands policies
DROP POLICY IF EXISTS "Brands can manage their own data" ON brands;
DROP POLICY IF EXISTS "Artists can view brand profiles" ON brands;

CREATE POLICY "Brands can manage their own data" ON brands
  FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "Artists can view brand profiles" ON brands
  FOR SELECT USING (
    EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'artist')
  );

-- Subscriptions policies
DROP POLICY IF EXISTS "Fans can view their own subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "Artists can view their subscribers" ON subscriptions;
DROP POLICY IF EXISTS "Fans can create subscriptions" ON subscriptions;
DROP POLICY IF EXISTS "System can update subscription status" ON subscriptions;

CREATE POLICY "Fans can view their own subscriptions" ON subscriptions
  FOR SELECT USING (auth.uid() = fan_id);
CREATE POLICY "Artists can view their subscribers" ON subscriptions
  FOR SELECT USING (
    EXISTS(SELECT 1 FROM artists WHERE user_id = auth.uid() AND id = artist_id)
  );
CREATE POLICY "Fans can create subscriptions" ON subscriptions
  FOR INSERT WITH CHECK (auth.uid() = fan_id);
CREATE POLICY "System can update subscription status" ON subscriptions
  FOR UPDATE USING (true);

-- Content items policies
DROP POLICY IF EXISTS "Artists can manage their content" ON content_items;
DROP POLICY IF EXISTS "Subscribers can view unlocked content" ON content_items;

CREATE POLICY "Artists can manage their content" ON content_items
  FOR ALL USING (
    EXISTS(SELECT 1 FROM artists WHERE user_id = auth.uid() AND id = artist_id)
  );
CREATE POLICY "Subscribers can view unlocked content" ON content_items
  FOR SELECT USING (
    (unlock_date IS NULL OR unlock_date <= now())
    AND EXISTS(
      SELECT 1 FROM subscriptions s
      JOIN artists a ON s.artist_id = a.id
      WHERE s.fan_id = auth.uid()
      AND a.id = artist_id
      AND s.status = 'active'
    )
  );

-- 🎵 NEW: Audio intelligence table policies
-- Audio features policies
CREATE POLICY "Artists can view their content audio features" ON audio_features
  FOR SELECT USING (
    EXISTS(
      SELECT 1 FROM content_items ci
      JOIN artists a ON ci.artist_id = a.id
      WHERE ci.id = content_id AND a.user_id = auth.uid()
    )
  );

CREATE POLICY "System can manage audio features" ON audio_features
  FOR ALL USING (true); -- Processing services need full access

-- Mood tags policies
CREATE POLICY "Artists can view their content mood tags" ON mood_tags
  FOR SELECT USING (
    EXISTS(
      SELECT 1 FROM content_items ci
      JOIN artists a ON ci.artist_id = a.id
      WHERE ci.id = content_id AND a.user_id = auth.uid()
    )
  );

CREATE POLICY "System can manage mood tags" ON mood_tags
  FOR ALL USING (true); -- Processing services need full access

-- Lyrics policies
CREATE POLICY "Artists can manage their content lyrics" ON lyrics
  FOR ALL USING (
    EXISTS(
      SELECT 1 FROM content_items ci
      JOIN artists a ON ci.artist_id = a.id
      WHERE ci.id = content_id AND a.user_id = auth.uid()
    )
  );

CREATE POLICY "Subscribers can view lyrics of unlocked content" ON lyrics
  FOR SELECT USING (
    EXISTS(
      SELECT 1 FROM content_items ci
      JOIN artists a ON ci.artist_id = a.id
      JOIN subscriptions s ON s.artist_id = a.id
      WHERE ci.id = content_id
      AND s.fan_id = auth.uid()
      AND s.status = 'active'
      AND (ci.unlock_date IS NULL OR ci.unlock_date <= now())
    )
  );

-- Audio processing jobs policies
CREATE POLICY "Artists can view their content processing jobs" ON audio_processing_jobs
  FOR SELECT USING (
    EXISTS(
      SELECT 1 FROM content_items ci
      JOIN artists a ON ci.artist_id = a.id
      WHERE ci.id = content_id AND a.user_id = auth.uid()
    )
  );

CREATE POLICY "System can manage processing jobs" ON audio_processing_jobs
  FOR ALL USING (true); -- Processing services need full access

-- Campaign policies
DROP POLICY IF EXISTS "Brands can manage their campaigns" ON campaigns;
DROP POLICY IF EXISTS "Artists can view relevant campaigns" ON campaigns;

CREATE POLICY "Brands can manage their campaigns" ON campaigns
  FOR ALL USING (
    EXISTS(SELECT 1 FROM brands WHERE user_id = auth.uid() AND id = brand_id)
  );
CREATE POLICY "Artists can view relevant campaigns" ON campaigns
  FOR SELECT USING (
    status = 'active'
    AND EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'artist')
  );

-- ✅ FIXED: Campaign placements policies (only if table exists)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'campaign_placements') THEN
    DROP POLICY IF EXISTS "Brands can view their campaign placements" ON campaign_placements;
    DROP POLICY IF EXISTS "Artists can view placements for their content" ON campaign_placements;
    DROP POLICY IF EXISTS "Brands can manage their campaign placements" ON campaign_placements;
    DROP POLICY IF EXISTS "Artists can update placement status" ON campaign_placements;

    CREATE POLICY "Brands can view their campaign placements" ON campaign_placements
      FOR SELECT USING (
        EXISTS(
          SELECT 1 FROM campaigns c 
          JOIN brands b ON c.brand_id = b.id 
          WHERE c.id = campaign_id AND b.user_id = auth.uid()
        )
      );
    CREATE POLICY "Artists can view placements for their content" ON campaign_placements
      FOR SELECT USING (
        EXISTS(SELECT 1 FROM artists WHERE id = artist_id AND user_id = auth.uid())
      );
    CREATE POLICY "Brands can manage their campaign placements" ON campaign_placements
      FOR ALL USING (
        EXISTS(
          SELECT 1 FROM campaigns c 
          JOIN brands b ON c.brand_id = b.id 
          WHERE c.id = campaign_id AND b.user_id = auth.uid()
        )
      );
    CREATE POLICY "Artists can update placement status" ON campaign_placements
      FOR UPDATE USING (
        EXISTS(SELECT 1 FROM artists WHERE id = artist_id AND user_id = auth.uid())
      );
  END IF;
END $$;

-- Engagement log policies
DROP POLICY IF EXISTS "Users can view their own engagement log" ON media_engagement_log;
DROP POLICY IF EXISTS "System can insert engagement logs" ON media_engagement_log;

CREATE POLICY "Users can view their own engagement log" ON media_engagement_log
  FOR SELECT USING (auth.uid() = user_id AND is_anonymous = false);
CREATE POLICY "System can insert engagement logs" ON media_engagement_log
  FOR INSERT WITH CHECK (true);

-- Transactions policies
DROP POLICY IF EXISTS "Users can view their own transactions" ON transactions;
DROP POLICY IF EXISTS "System can manage transactions" ON transactions;

CREATE POLICY "Users can view their own transactions" ON transactions
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "System can manage transactions" ON transactions
  FOR ALL USING (true);

-- ===============================================
-- SCRIPT 005: STORED FUNCTIONS
-- ===============================================

-- Function to unlock content based on schedule and milestones
CREATE OR REPLACE FUNCTION unlock_scheduled_content()
RETURNS TABLE(unlocked_count INTEGER) AS $$
DECLARE
  unlocked_count INTEGER := 0;
BEGIN
  -- Update content items that should be unlocked
  UPDATE content_items 
  SET unlock_date = now()
  WHERE 
    (unlock_date IS NOT NULL AND unlock_date <= now())
    OR (
      milestone_condition IS NOT NULL 
      AND check_milestone_condition(id, milestone_condition)
    );
  
  GET DIAGNOSTICS unlocked_count = ROW_COUNT;
  RETURN QUERY SELECT unlocked_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check milestone conditions
CREATE OR REPLACE FUNCTION check_milestone_condition(
  content_id UUID, 
  condition JSONB
) RETURNS BOOLEAN AS $$
DECLARE
  milestone_type TEXT;
  threshold INTEGER;
  current_count INTEGER;
  artist_id_val UUID;
BEGIN
  milestone_type := condition->>'type';
  threshold := (condition->>'threshold')::INTEGER;
  
  SELECT artist_id INTO artist_id_val FROM content_items WHERE id = content_id;
  
  CASE milestone_type
    WHEN 'subscriber_count' THEN
      SELECT COUNT(*) INTO current_count 
      FROM subscriptions 
      WHERE artist_id = artist_id_val AND status = 'active';
      
    WHEN 'total_revenue' THEN
      SELECT COALESCE(SUM(price_cents), 0) INTO current_count
      FROM subscriptions 
      WHERE artist_id = artist_id_val AND status = 'active';
      
    ELSE
      RETURN FALSE;
  END CASE;
  
  RETURN current_count >= threshold;
END;
$$ LANGUAGE plpgsql;

-- Function to get artist analytics
CREATE OR REPLACE FUNCTION get_artist_analytics(artist_user_id UUID)
RETURNS TABLE(
  total_subscribers INTEGER,
  monthly_revenue_cents INTEGER,
  total_content_items INTEGER,
  engagement_rate DECIMAL,
  growth_rate DECIMAL
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    (SELECT COUNT(*)::INTEGER 
     FROM subscriptions s 
     JOIN artists a ON s.artist_id = a.id 
     WHERE a.user_id = artist_user_id AND s.status = 'active') as total_subscribers,
    
    (SELECT COALESCE(SUM(s.price_cents), 0)::INTEGER 
     FROM subscriptions s 
     JOIN artists a ON s.artist_id = a.id 
     WHERE a.user_id = artist_user_id AND s.status = 'active') as monthly_revenue_cents,
    
    (SELECT COUNT(*)::INTEGER 
     FROM content_items ci 
     JOIN artists a ON ci.artist_id = a.id 
     WHERE a.user_id = artist_user_id) as total_content_items,
    
    (SELECT COALESCE(AVG(
       CASE WHEN mel.event_type IN ('play', 'like', 'share') THEN 1.0 ELSE 0.0 END
     ), 0.0)::DECIMAL 
     FROM media_engagement_log mel 
     JOIN content_items ci ON mel.content_id = ci.id 
     JOIN artists a ON ci.artist_id = a.id 
     WHERE a.user_id = artist_user_id 
     AND mel.timestamp >= now() - interval '30 days') as engagement_rate,
    
    (SELECT COALESCE(
       (COUNT(CASE WHEN s.created_at >= now() - interval '30 days' THEN 1 END)::DECIMAL / 
        NULLIF(COUNT(CASE WHEN s.created_at >= now() - interval '60 days' 
                          AND s.created_at < now() - interval '30 days' THEN 1 END), 0) - 1) * 100,
       0.0
     )::DECIMAL
     FROM subscriptions s 
     JOIN artists a ON s.artist_id = a.id 
     WHERE a.user_id = artist_user_id) as growth_rate;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update campaign metrics
CREATE OR REPLACE FUNCTION update_campaign_metrics(
  campaign_id_param UUID,
  impression_delta INTEGER DEFAULT 0,
  click_delta INTEGER DEFAULT 0,
  conversion_delta INTEGER DEFAULT 0,
  spend_delta_cents INTEGER DEFAULT 0
) RETURNS VOID AS $$
BEGIN
  UPDATE campaigns 
  SET 
    total_impressions = total_impressions + impression_delta,
    total_clicks = total_clicks + click_delta,
    total_conversions = total_conversions + conversion_delta,
    spend_cents = spend_cents + spend_delta_cents,
    updated_at = now()
  WHERE id = campaign_id_param;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 🎵 NEW: Function to queue audio processing jobs
CREATE OR REPLACE FUNCTION queue_audio_processing(
  content_id_param UUID,
  job_types TEXT[] DEFAULT ARRAY['audio_features', 'mood_analysis']
) RETURNS INTEGER AS $$
DECLARE
  job_type_enum job_type;
  queued_count INTEGER := 0;
BEGIN
  -- Only queue jobs for audio content
  IF NOT EXISTS (
    SELECT 1 FROM content_items 
    WHERE id = content_id_param AND content_type = 'audio'
  ) THEN
    RETURN 0;
  END IF;

  -- Queue each requested job type
  FOREACH job_type_enum IN ARRAY job_types::job_type[]
  LOOP
    -- Only queue if not already processed
    IF NOT EXISTS (
      SELECT 1 FROM audio_processing_jobs
      WHERE content_id = content_id_param 
      AND job_type = job_type_enum 
      AND status IN ('completed', 'running', 'queued')
    ) THEN
      INSERT INTO audio_processing_jobs (content_id, job_type, status)
      VALUES (content_id_param, job_type_enum, 'queued');
      queued_count := queued_count + 1;
    END IF;
  END LOOP;

  RETURN queued_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 🎵 NEW: Function to get next processing job
CREATE OR REPLACE FUNCTION get_next_processing_job(
  job_type_filter job_type DEFAULT NULL
) RETURNS TABLE(
  job_id UUID,
  content_id UUID,
  job_type job_type,
  file_path TEXT,
  attempts INTEGER
) AS $$
BEGIN
  RETURN QUERY
  UPDATE audio_processing_jobs apj
  SET 
    status = 'running',
    started_at = now(),
    attempts = attempts + 1
  FROM content_items ci
  WHERE apj.content_id = ci.id
  AND apj.status = 'queued'
  AND apj.attempts < apj.max_attempts
  AND (job_type_filter IS NULL OR apj.job_type = job_type_filter)
  AND apj.id = (
    SELECT id FROM audio_processing_jobs
    WHERE status = 'queued'
    AND attempts < max_attempts
    AND (job_type_filter IS NULL OR job_type = job_type_filter)
    ORDER BY scheduled_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING apj.id, apj.content_id, apj.job_type, ci.file_path, apj.attempts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ===============================================
-- SCRIPT 006: DASHBOARD VIEWS (FIXED)
-- ===============================================

-- Artist dashboard view
CREATE OR REPLACE VIEW artist_dashboard_view AS
SELECT 
  a.id as artist_id,
  a.user_id,
  a.artist_name,
  COUNT(DISTINCT s.id) as subscriber_count,
  COALESCE(SUM(s.price_cents), 0) as monthly_revenue_cents,
  COUNT(DISTINCT ci.id) as content_count,
  COUNT(DISTINCT ci.id) FILTER (WHERE ci.unlock_date <= now()) as unlocked_content_count,
  COALESCE(AVG(
    CASE WHEN mel.event_type IN ('play', 'like', 'share') THEN 1.0 ELSE 0.0 END
  ), 0.0) as engagement_rate,
  MAX(ci.created_at) as last_upload_date
FROM artists a
LEFT JOIN subscriptions s ON a.id = s.artist_id AND s.status = 'active'
LEFT JOIN content_items ci ON a.id = ci.artist_id
LEFT JOIN media_engagement_log mel ON ci.id = mel.content_id 
  AND mel.timestamp >= now() - interval '30 days'
GROUP BY a.id, a.user_id, a.artist_name;

-- ✅ FIXED: Brand dashboard view with safe column handling
CREATE OR REPLACE VIEW brand_dashboard_view AS
SELECT 
  b.id as brand_id,
  b.user_id,
  b.brand_name,
  COUNT(DISTINCT c.id) as total_campaigns,
  COUNT(DISTINCT c.id) FILTER (WHERE c.status = 'active') as active_campaigns,
  COALESCE(SUM(c.budget_cents), 0) as total_budget_cents,
  -- ✅ FIXED: Use budget_cents as safe fallback for now
  COALESCE(SUM(c.budget_cents), 0) as total_spend_cents,
  COALESCE(SUM(COALESCE(c.total_impressions, 0)), 0) as total_impressions,
  COALESCE(SUM(COALESCE(c.total_clicks, 0)), 0) as total_clicks,
  COALESCE(SUM(COALESCE(c.total_conversions, 0)), 0) as total_conversions,
  CASE 
    WHEN SUM(COALESCE(c.total_impressions, 0)) > 0 
    THEN (SUM(COALESCE(c.total_clicks, 0))::DECIMAL / SUM(COALESCE(c.total_impressions, 0)) * 100)
    ELSE 0.0 
  END as overall_ctr
FROM brands b
LEFT JOIN campaigns c ON b.id = c.brand_id
GROUP BY b.id, b.user_id, b.brand_name;

-- Content engagement summary view
CREATE OR REPLACE VIEW content_engagement_view AS
SELECT 
  ci.id as content_id,
  ci.artist_id,
  ci.title,
  ci.content_type,
  ci.unlock_date,
  COUNT(mel.id) as total_engagements,
  COUNT(DISTINCT mel.user_id) as unique_users,
  COUNT(mel.id) FILTER (WHERE mel.event_type = 'play') as plays,
  COUNT(mel.id) FILTER (WHERE mel.event_type = 'like') as likes,
  COUNT(mel.id) FILTER (WHERE mel.event_type = 'share') as shares,
  CASE 
    WHEN COUNT(DISTINCT mel.user_id) > 0 
    THEN (COUNT(mel.id)::DECIMAL / COUNT(DISTINCT mel.user_id))
    ELSE 0.0 
  END as engagement_per_user
FROM content_items ci
LEFT JOIN media_engagement_log mel ON ci.id = mel.content_id
GROUP BY ci.id, ci.artist_id, ci.title, ci.content_type, ci.unlock_date;

-- 🎵 NEW: Audio intelligence view
CREATE OR REPLACE VIEW content_intelligence_view AS
SELECT 
  ci.id as content_id,
  ci.title,
  ci.artist_id,
  ci.content_type,
  ci.processing_status,
  af.bpm,
  af.key,
  af.mode,
  af.energy,
  af.valence,
  af.confidence as audio_confidence,
  af.source as audio_source,
  mt.tags as mood_tags,
  mt.confidence as mood_confidence,
  l.is_synced as has_synced_lyrics,
  l.language as lyric_language,
  CASE WHEN l.text IS NOT NULL THEN true ELSE false END as has_lyrics
FROM content_items ci
LEFT JOIN audio_features af ON ci.id = af.content_id
LEFT JOIN mood_tags mt ON ci.id = mt.content_id
LEFT JOIN lyrics l ON ci.id = l.content_id
WHERE ci.content_type = 'audio';

-- ===============================================
-- SCRIPT 007: PERFORMANCE INDEXES (FIXED)
-- ===============================================

-- ✅ FIXED: Remove CONCURRENTLY to allow transaction block
CREATE INDEX IF NOT EXISTS idx_subscriptions_artist_status_active 
  ON subscriptions(artist_id, status) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_content_items_artist_unlock 
  ON content_items(artist_id, unlock_date) WHERE unlock_date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_engagement_log_user_timestamp 
  ON media_engagement_log(user_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_campaigns_active 
  ON campaigns(brand_id, status) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_media_ids_active_role 
  ON media_ids(user_uuid, role) WHERE is_active = true;

-- GIN indexes for JSONB columns
CREATE INDEX IF NOT EXISTS idx_media_ids_privacy_settings 
  ON media_ids USING GIN(privacy_settings);

CREATE INDEX IF NOT EXISTS idx_campaigns_targeting 
  ON campaigns USING GIN(targeting_criteria);

CREATE INDEX IF NOT EXISTS idx_content_items_metadata 
  ON content_items USING GIN(metadata);

-- Specialized indexes for analytics
CREATE INDEX IF NOT EXISTS idx_engagement_log_event_timestamp 
  ON media_engagement_log(event_type, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_type_status 
  ON transactions(transaction_type, status);

-- 🎵 NEW: Audio intelligence performance indexes
CREATE INDEX IF NOT EXISTS idx_audio_features_bpm_energy 
  ON audio_features(bpm, energy) WHERE bpm IS NOT NULL AND energy IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_mood_tags_confidence 
  ON mood_tags(confidence DESC) WHERE confidence > 0.7;

CREATE INDEX IF NOT EXISTS idx_processing_jobs_retry 
  ON audio_processing_jobs(attempts, max_attempts, scheduled_at) 
  WHERE status = 'queued';

-- ===============================================
-- SCRIPT 008: DATA MIGRATION & CLEANUP
-- ===============================================

-- Fix authenticator search path
ALTER ROLE authenticator SET search_path = "public","auth",pg_catalog;

-- Create missing profiles for existing users
INSERT INTO profiles (id, display_name, role, email_verified, onboarding_completed)
SELECT 
  u.id,
  COALESCE(u.raw_user_meta_data->>'display_name', split_part(u.email, '@', 1)),
  COALESCE(u.raw_user_meta_data->>'role', 'fan')::user_role,
  u.email_confirmed_at IS NOT NULL,
  false
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
WHERE p.id IS NULL;

-- Create missing media_ids for existing users
INSERT INTO media_ids (user_uuid, role, interests, genre_preferences, privacy_settings, version, is_active)
SELECT 
  u.id,
  COALESCE(p.role, 'fan'),
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
FROM auth.users u
JOIN profiles p ON p.id = u.id
LEFT JOIN media_ids m ON m.user_uuid = u.id AND m.role = p.role
WHERE m.id IS NULL;

-- Clean up any orphaned records
DELETE FROM media_ids WHERE user_uuid NOT IN (SELECT id FROM auth.users);
DELETE FROM profiles WHERE id NOT IN (SELECT id FROM auth.users);

-- Update any existing media_ids that don't have role/version/is_active
UPDATE media_ids 
SET 
  role = COALESCE(role, 'fan'),
  version = COALESCE(version, 1),
  is_active = COALESCE(is_active, true)
WHERE role IS NULL OR version IS NULL OR is_active IS NULL;

-- ===============================================
-- SCRIPT 010: ADVANCED METADATA SYSTEM (NEW)
-- ===============================================
-- 🎵 NEW: Advanced metadata features for SoundCloud-inspired upload system

-- 1. CRITICAL: Rename artists table to match frontend expectations
ALTER TABLE artists RENAME TO artist_profiles;

-- 2. Update foreign key constraints to use new table name
ALTER TABLE content_items 
DROP CONSTRAINT IF EXISTS content_items_artist_id_fkey,
ADD CONSTRAINT content_items_artist_id_fkey 
FOREIGN KEY (artist_id) REFERENCES artist_profiles(id) ON DELETE CASCADE;

ALTER TABLE subscriptions
DROP CONSTRAINT IF EXISTS subscriptions_artist_id_fkey,
ADD CONSTRAINT subscriptions_artist_id_fkey 
FOREIGN KEY (artist_id) REFERENCES artist_profiles(id) ON DELETE CASCADE;

-- 3. Add advanced metadata columns to content_items
ALTER TABLE content_items ADD COLUMN IF NOT EXISTS
  -- Advanced Details
  buy_link_url TEXT,
  buy_link_title TEXT,
  record_label TEXT,
  release_date DATE,
  publisher TEXT,
  isrc TEXT,
  explicit BOOLEAN DEFAULT false,
  p_line TEXT,
  
  -- Album Linking  
  album_id UUID,
  album_name TEXT,
  track_number INTEGER,
  
  -- Permissions/Access
  enable_direct_downloads BOOLEAN DEFAULT false,
  offline_listening BOOLEAN DEFAULT false,
  include_in_rss BOOLEAN DEFAULT true,
  display_embed_code BOOLEAN DEFAULT true,
  enable_app_playback BOOLEAN DEFAULT true,
  allow_comments BOOLEAN DEFAULT true,
  show_comments_public BOOLEAN DEFAULT true,
  show_insights_public BOOLEAN aDEFAULT false,
  
  -- Geoblocking
  availability_scope TEXT DEFAULT 'worldwide' CHECK (availability_scope IN ('worldwide', 'exclusive_regions', 'blocked_regions')),
  availability_regions TEXT[], -- Array of ISO country codes
  
  -- Preview/Clips (stored as JSONB)
  preview_clip JSONB, -- {start_sec, duration_sec}
  visual_clip JSONB, -- {file_path, duration_sec, loop_enabled}
  
  -- License Type (including BSL)
  license_type TEXT DEFAULT 'all_rights_reserved' CHECK (license_type IN (
    'all_rights_reserved', 'cc_by', 'cc_by_sa', 'cc_by_nc', 
    'cc_by_nc_sa', 'cc_by_nd', 'cc_by_nc_nd', 'bsl'
  ));

-- 4. Create albums table
CREATE TABLE IF NOT EXISTS albums (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  artist_id UUID NOT NULL REFERENCES artist_profiles(id) ON DELETE CASCADE,
  description TEXT,
  release_date DATE,
  artwork_url TEXT,
  total_tracks INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- 5. Add album foreign key constraint to content_items
ALTER TABLE content_items 
ADD CONSTRAINT content_items_album_id_fkey 
FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE SET NULL;

-- 6. Enhanced artist_profiles for upload features
ALTER TABLE artist_profiles ADD COLUMN IF NOT EXISTS
  record_label TEXT,
  publisher TEXT,
  bsl_enabled BOOLEAN DEFAULT false,
  bsl_tier TEXT CHECK (bsl_tier IN ('basic', 'premium', 'enterprise')),
  upload_preferences JSONB DEFAULT '{}';

-- 7. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_content_items_album_id ON content_items(album_id);
CREATE INDEX IF NOT EXISTS idx_content_items_isrc ON content_items(isrc) WHERE isrc IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_content_items_license ON content_items(license_type);
CREATE INDEX IF NOT EXISTS idx_content_items_availability ON content_items(availability_scope);
CREATE INDEX IF NOT EXISTS idx_albums_artist_id ON albums(artist_id);
CREATE INDEX IF NOT EXISTS idx_albums_release_date ON albums(release_date DESC);

-- 8. Enable RLS on albums table
ALTER TABLE albums ENABLE ROW LEVEL SECURITY;

-- 9. RLS Policies for albums
CREATE POLICY "Artists can manage their albums" ON albums
  FOR ALL USING (
    EXISTS(SELECT 1 FROM artist_profiles WHERE user_id = auth.uid() AND id = artist_id)
  );

CREATE POLICY "Public can view albums" ON albums
  FOR SELECT USING (true); -- Public album discovery

-- 10. Add unique constraint for ISRC (globally unique)
ALTER TABLE content_items ADD CONSTRAINT content_items_isrc_unique UNIQUE(isrc);

-- 11. Create trigger for albums updated_at
CREATE TRIGGER update_albums_updated_at BEFORE UPDATE ON albums
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 12. Function to auto-increment album track count
CREATE OR REPLACE FUNCTION update_album_track_count()
RETURNS TRIGGER AS $$
BEGIN
  -- When content is added to an album
  IF NEW.album_id IS NOT NULL AND (OLD.album_id IS NULL OR OLD.album_id != NEW.album_id) THEN
    UPDATE albums 
    SET total_tracks = (
      SELECT COUNT(*) FROM content_items WHERE album_id = NEW.album_id
    )
    WHERE id = NEW.album_id;
  END IF;
  
  -- When content is removed from an album
  IF OLD.album_id IS NOT NULL AND (NEW.album_id IS NULL OR OLD.album_id != NEW.album_id) THEN
    UPDATE albums 
    SET total_tracks = (
      SELECT COUNT(*) FROM content_items WHERE album_id = OLD.album_id
    )
    WHERE id = OLD.album_id;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 13. Create trigger for automatic track count updates
CREATE TRIGGER update_album_track_count_trigger
  AFTER INSERT OR UPDATE OR DELETE ON content_items
  FOR EACH ROW EXECUTE FUNCTION update_album_track_count();

-- 14. Function to validate ISRC format
CREATE OR REPLACE FUNCTION validate_isrc_format()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.isrc IS NOT NULL THEN
    -- ISRC format: CC-XXX-YY-NNNNN (12 characters total)
    IF NOT (NEW.isrc ~ '^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$') THEN
      RAISE EXCEPTION 'ISRC must be in format: CC-XXX-YY-NNNNN (Country-Registrant-Year-Designation)';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 15. Create trigger for ISRC validation
CREATE TRIGGER validate_isrc_trigger
  BEFORE INSERT OR UPDATE ON content_items
  FOR EACH ROW EXECUTE FUNCTION validate_isrc_format();

-- 16. Create function for BSL license eligibility check
CREATE OR REPLACE FUNCTION check_bsl_eligibility(artist_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  artist_record RECORD;
BEGIN
  SELECT bsl_enabled, verification_status INTO artist_record 
  FROM artist_profiles 
  WHERE id = artist_id;
  
  RETURN (artist_record.bsl_enabled = true AND artist_record.verification_status = 'verified');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 17. Add storage buckets for visual clips and lyrics documents
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  ('visual-clips', 'visual-clips', true, 52428800, ARRAY['video/mp4', 'video/quicktime', 'video/webm', 'video/avi']),
  ('lyrics-documents', 'lyrics-documents', false, 10485760, ARRAY['text/plain', 'application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
ON CONFLICT (id) DO NOTHING;

-- 18. Storage policies for visual clips
CREATE POLICY "Artists can upload visual clips" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'visual-clips' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Public can view visual clips" ON storage.objects
FOR SELECT USING (bucket_id = 'visual-clips');

-- 19. Storage policies for lyrics documents
CREATE POLICY "Artists can upload lyrics documents" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'lyrics-documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "Artists can view their lyrics documents" ON storage.objects
FOR SELECT USING (
  bucket_id = 'lyrics-documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- 20. Enhanced lyrics table to support OCR/NER extraction
ALTER TABLE lyrics ADD COLUMN IF NOT EXISTS
  extracted_metadata JSONB,
  confidence_scores JSONB,
  processing_errors TEXT[],
  processed_at TIMESTAMP;

-- ===============================================
-- END OF ENHANCED SQL LIBRARY v2.1
-- ===============================================

-- PHASE 2 ENHANCEMENTS COMPLETED:
-- ✅ Fixed storage bucket name ('artist-content')
-- ✅ Enhanced content_items table with audio intelligence fields
-- ✅ Added audio_features table for BPM/key/mood data
-- ✅ Added mood_tags table for human-readable tags
-- ✅ Added lyrics table for synchronized lyric content
-- ✅ Added audio_processing_jobs table for async processing
-- ✅ Enhanced RLS policies for new tables
-- ✅ Added processing functions and views
-- ✅ Added performance indexes for audio intelligence
-- 🚀 ADDED: Advanced metadata system with album management
-- 🚀 ADDED: BSL licensing support with eligibility checking
-- 🚀 ADDED: Visual clip storage and management
-- 🚀 ADDED: OCR/NER integration for lyrics processing
-- 🚀 ADDED: Comprehensive permission system
-- 🚀 ADDED: ISRC validation and geoblocking support
-- 
-- READY FOR DEPLOYMENT TO SUPABASE
-- Run these scripts in order on your Supabase instance
