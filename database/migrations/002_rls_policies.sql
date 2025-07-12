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

-- Profiles policies
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Public profile viewing for artist discovery
CREATE POLICY "Public can view artist profiles" ON profiles
  FOR SELECT USING (role = 'artist');

-- MediaID policies (strict privacy)
CREATE POLICY "Users can view their own MediaID" ON media_ids
  FOR SELECT USING (auth.uid() = user_uuid);

CREATE POLICY "Users can update their own MediaID" ON media_ids
  FOR UPDATE USING (auth.uid() = user_uuid);

CREATE POLICY "Users can insert their own MediaID" ON media_ids
  FOR INSERT WITH CHECK (auth.uid() = user_uuid);

-- Artists policies
CREATE POLICY "Artists can manage their own data" ON artists
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Public can view artist profiles" ON artists
  FOR SELECT USING (true); -- Public discovery

-- Brands policies
CREATE POLICY "Brands can manage their own data" ON brands
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Artists can view brand profiles" ON brands
  FOR SELECT USING (
    EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'artist')
  );

-- Subscriptions policies
CREATE POLICY "Fans can view their own subscriptions" ON subscriptions
  FOR SELECT USING (auth.uid() = fan_id);

CREATE POLICY "Artists can view their subscribers" ON subscriptions
  FOR SELECT USING (
    EXISTS(SELECT 1 FROM artists WHERE user_id = auth.uid() AND id = artist_id)
  );

CREATE POLICY "Fans can create subscriptions" ON subscriptions
  FOR INSERT WITH CHECK (auth.uid() = fan_id);

CREATE POLICY "System can update subscription status" ON subscriptions
  FOR UPDATE USING (true); -- Handled by Stripe webhooks

-- Content items policies
CREATE POLICY "Artists can manage their content" ON content_items
  FOR ALL USING (
    EXISTS(SELECT 1 FROM artists WHERE user_id = auth.uid() AND id = artist_id)
  );

CREATE POLICY "Subscribers can view unlocked content" ON content_items
  FOR SELECT USING (
    -- Content is unlocked AND user is subscribed to artist
    (unlock_date IS NULL OR unlock_date <= now())
    AND EXISTS(
      SELECT 1 FROM subscriptions s
      JOIN artists a ON s.artist_id = a.id
      WHERE s.fan_id = auth.uid()
      AND a.id = artist_id
      AND s.status = 'active'
    )
  );

-- Campaign policies
CREATE POLICY "Brands can manage their campaigns" ON campaigns
  FOR ALL USING (
    EXISTS(SELECT 1 FROM brands WHERE user_id = auth.uid() AND id = brand_id)
  );

CREATE POLICY "Artists can view relevant campaigns" ON campaigns
  FOR SELECT USING (
    status = 'active'
    AND EXISTS(SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'artist')
  );

-- Engagement log policies (privacy-first)
CREATE POLICY "Users can view their own engagement log" ON media_engagement_log
  FOR SELECT USING (auth.uid() = user_id AND is_anonymous = false);

CREATE POLICY "System can insert engagement logs" ON media_engagement_log
  FOR INSERT WITH CHECK (true);

-- Transactions policies
CREATE POLICY "Users can view their own transactions" ON transactions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "System can manage transactions" ON transactions
  FOR ALL USING (true); -- Handled by secure backend functions 