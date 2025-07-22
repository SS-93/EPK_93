-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- Create enum types for better data integrity
CREATE TYPE user_role AS ENUM ('fan', 'artist', 'brand', 'admin');
CREATE TYPE subscription_status AS ENUM ('active', 'canceled', 'paused', 'expired');
CREATE TYPE content_type AS ENUM ('audio', 'video', 'image', 'document');
CREATE TYPE campaign_status AS ENUM ('draft', 'active', 'paused', 'completed');

-- Profiles table (extends Supabase auth.users)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_url TEXT,
  role user_role NOT NULL DEFAULT 'fan',
  email_verified BOOLEAN DEFAULT FALSE,
  onboarding_completed BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- MediaID Table (your suggested schema with enhancements)
CREATE TABLE media_ids (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uuid UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  interests TEXT[] DEFAULT '{}',
  genre_preferences TEXT[] DEFAULT '{}',
  content_flags JSONB DEFAULT '{}', -- { "likes": [...], "dislikes": [...], "mood": "energetic" }
  location_code TEXT,
  profile_embedding VECTOR(1536), -- OpenAI-style embedding for matching
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

-- Artists table
CREATE TABLE artists (
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

-- Brands table
CREATE TABLE brands (
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

-- Subscriptions table
CREATE TABLE subscriptions (
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

-- Content items table (Artist Locker)
CREATE TABLE content_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_id UUID REFERENCES artists(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  content_type content_type NOT NULL,
  file_path TEXT NOT NULL,
  file_size_bytes BIGINT,
  duration_seconds INTEGER, -- for audio/video
  unlock_date TIMESTAMP,
  milestone_condition JSONB, -- { "type": "subscriber_count", "threshold": 100 }
  is_premium BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Brand campaigns table
CREATE TABLE campaigns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  brand_id UUID REFERENCES brands(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  targeting_criteria JSONB NOT NULL, -- MediaID-based targeting
  budget_cents INTEGER NOT NULL,
  payment_model TEXT NOT NULL, -- 'flat_fee', 'pay_per_engagement', 'pay_per_conversion'
  status campaign_status DEFAULT 'draft',
  start_date TIMESTAMP,
  end_date TIMESTAMP,
  assets JSONB DEFAULT '{}', -- URLs and metadata for campaign assets
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Media engagement log (anonymous by default)
CREATE TABLE media_engagement_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  content_id UUID REFERENCES content_items(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL, -- 'view', 'play', 'like', 'share', 'download'
  session_id TEXT,
  user_agent TEXT,
  ip_address INET,
  is_anonymous BOOLEAN DEFAULT TRUE,
  metadata JSONB DEFAULT '{}',
  timestamp TIMESTAMP DEFAULT now()
);

-- Transactions table
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  amount_cents INTEGER NOT NULL,
  currency TEXT DEFAULT 'USD',
  transaction_type TEXT NOT NULL, -- 'subscription', 'campaign_payment', 'payout'
  status TEXT DEFAULT 'pending',
  stripe_payment_intent_id TEXT,
  description TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Create indexes for performance
CREATE INDEX idx_profiles_role ON profiles(role);
CREATE INDEX idx_media_ids_user_uuid ON media_ids(user_uuid);
CREATE INDEX idx_media_ids_interests ON media_ids USING GIN(interests);
CREATE INDEX idx_subscriptions_fan_artist ON subscriptions(fan_id, artist_id);
CREATE INDEX idx_subscriptions_status ON subscriptions(status);
CREATE INDEX idx_content_items_artist ON content_items(artist_id);
CREATE INDEX idx_content_items_unlock_date ON content_items(unlock_date);
CREATE INDEX idx_campaigns_brand ON campaigns(brand_id);
CREATE INDEX idx_campaigns_status ON campaigns(status);
CREATE INDEX idx_engagement_log_user ON media_engagement_log(user_id);
CREATE INDEX idx_engagement_log_content ON media_engagement_log(content_id);
CREATE INDEX idx_engagement_log_timestamp ON media_engagement_log(timestamp);
CREATE INDEX idx_transactions_user ON transactions(user_id);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_media_ids_updated_at BEFORE UPDATE ON media_ids
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_artists_updated_at BEFORE UPDATE ON artists
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_brands_updated_at BEFORE UPDATE ON brands
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_content_items_updated_at BEFORE UPDATE ON content_items
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_campaigns_updated_at BEFORE UPDATE ON campaigns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column(); 