-- Publish all tracks for discovery
-- Since this is a discovery platform, tracks should be visible by default

UPDATE content_items
SET is_published = true
WHERE is_published = false;