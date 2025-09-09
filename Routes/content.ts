import { Router, Request, Response } from 'express';
import { supabase } from '../lib/supabaseClient';

const router = Router();

// Middleware to get authenticated user
const requireAuth = async (req: Request, res: Response, next: any) => {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) {
    return res.status(401).json({ error: 'No authorization token provided' });
  }

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return res.status(401).json({ error: 'Invalid token' });
  }

  req.user = user;
  next();
};

// Get artist profile ID for authenticated user
const getArtistId = async (userId: string) => {
  const { data, error } = await supabase
    .from('artist_profiles')
    .select('id')
    .eq('user_id', userId)
    .single();
  
  if (error) throw new Error('Artist profile not found');
  return data.id;
};

// ==========================================
// CONTENT MANAGEMENT ENDPOINTS
// ==========================================

// Update content metadata
router.put('/content/:id/metadata', requireAuth, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const metadata = req.body;
    
    // Validate user owns this content
    const artistId = await getArtistId(req.user.id);
    const { data: existingContent, error: fetchError } = await supabase
      .from('content_items')
      .select('id')
      .eq('id', id)
      .eq('artist_id', artistId)
      .single();
    
    if (fetchError || !existingContent) {
      return res.status(404).json({ error: 'Content not found or access denied' });
    }
    
    // Update content with new metadata
    const { data, error } = await supabase
      .from('content_items')
      .update(metadata)
      .eq('id', id)
      .select()
      .single();
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json({ success: true, data });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get content with full metadata
router.get('/content/:id/metadata', requireAuth, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    
    const { data, error } = await supabase
      .from('content_items')
      .select('*')
      .eq('id', id)
      .single();
    
    if (error) {
      return res.status(404).json({ error: 'Content not found' });
    }
    
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==========================================
// ALBUM MANAGEMENT ENDPOINTS
// ==========================================

// Get all albums for artist
router.get('/albums', requireAuth, async (req: Request, res: Response) => {
  try {
    const artistId = await getArtistId(req.user.id);
    
    const { data, error } = await supabase
      .from('albums')
      .select(`
        *,
        tracks:content_items(id, title, track_number, duration_seconds)
      `)
      .eq('artist_id', artistId)
      .order('created_at', { ascending: false });
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create new album
router.post('/albums', requireAuth, async (req: Request, res: Response) => {
  try {
    const { name, description, release_date, artwork_url } = req.body;
    const artistId = await getArtistId(req.user.id);
    
    if (!name) {
      return res.status(400).json({ error: 'Album name is required' });
    }
    
    const { data, error } = await supabase
      .from('albums')
      .insert({
        name,
        description,
        release_date,
        artwork_url,
        artist_id: artistId
      })
      .select()
      .single();
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.status(201).json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update album
router.put('/albums/:id', requireAuth, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const updates = req.body;
    const artistId = await getArtistId(req.user.id);
    
    // Verify ownership
    const { data: album, error: fetchError } = await supabase
      .from('albums')
      .select('id')
      .eq('id', id)
      .eq('artist_id', artistId)
      .single();
    
    if (fetchError || !album) {
      return res.status(404).json({ error: 'Album not found or access denied' });
    }
    
    const { data, error } = await supabase
      .from('albums')
      .update(updates)
      .eq('id', id)
      .select()
      .single();
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete album
router.delete('/albums/:id', requireAuth, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const artistId = await getArtistId(req.user.id);
    
    // Verify ownership and get track count
    const { data: album, error: fetchError } = await supabase
      .from('albums')
      .select('id, total_tracks')
      .eq('id', id)
      .eq('artist_id', artistId)
      .single();
    
    if (fetchError || !album) {
      return res.status(404).json({ error: 'Album not found or access denied' });
    }
    
    if (album.total_tracks > 0) {
      return res.status(400).json({ 
        error: 'Cannot delete album with tracks. Remove tracks first.' 
      });
    }
    
    const { error } = await supabase
      .from('albums')
      .delete()
      .eq('id', id);
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json({ success: true, message: 'Album deleted' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get album tracks
router.get('/albums/:id/tracks', requireAuth, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    
    const { data, error } = await supabase
      .from('content_items')
      .select('*')
      .eq('album_id', id)
      .order('track_number', { ascending: true });
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==========================================
// LYRICS MANAGEMENT ENDPOINTS
// ==========================================

// Add/update lyrics for content
router.post('/content/:id/lyrics', requireAuth, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { text, synchronized, language, rights_cleared } = req.body;
    const artistId = await getArtistId(req.user.id);
    
    // Verify content ownership
    const { data: content, error: fetchError } = await supabase
      .from('content_items')
      .select('id')
      .eq('id', id)
      .eq('artist_id', artistId)
      .single();
    
    if (fetchError || !content) {
      return res.status(404).json({ error: 'Content not found or access denied' });
    }
    
    const lyricsData = {
      text,
      synchronized: synchronized || false,
      language: language || 'en',
      rights_cleared: rights_cleared || false,
      created_at: new Date().toISOString()
    };
    
    const { data, error } = await supabase
      .from('content_items')
      .update({ lyrics: lyricsData })
      .eq('id', id)
      .select()
      .single();
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json({ success: true, lyrics: data.lyrics });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==========================================
// VISUAL CLIP MANAGEMENT ENDPOINTS
// ==========================================

// Upload visual clip metadata
router.post('/content/:id/visual-clip', requireAuth, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { file_path, duration_sec, loop_enabled } = req.body;
    const artistId = await getArtistId(req.user.id);
    
    // Verify content ownership
    const { data: content, error: fetchError } = await supabase
      .from('content_items')
      .select('id')
      .eq('id', id)
      .eq('artist_id', artistId)
      .single();
    
    if (fetchError || !content) {
      return res.status(404).json({ error: 'Content not found or access denied' });
    }
    
    const visualClipData = {
      file_path,
      duration_sec: duration_sec || 30,
      loop_enabled: loop_enabled !== false,
      created_at: new Date().toISOString()
    };
    
    const { data, error } = await supabase
      .from('content_items')
      .update({ visual_clip: visualClipData })
      .eq('id', id)
      .select()
      .single();
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json({ success: true, visual_clip: data.visual_clip });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ==========================================
// BSL LICENSE MANAGEMENT ENDPOINTS
// ==========================================

// Check BSL eligibility for artist
router.get('/bsl/eligible', requireAuth, async (req: Request, res: Response) => {
  try {
    const artistId = await getArtistId(req.user.id);
    
    const { data, error } = await supabase
      .rpc('check_bsl_eligibility', { artist_id: artistId });
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json({ eligible: data });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Enable BSL for track
router.post('/bsl/enable', requireAuth, async (req: Request, res: Response) => {
  try {
    const { content_id } = req.body;
    const artistId = await getArtistId(req.user.id);
    
    // Check BSL eligibility
    const { data: eligible, error: eligibilityError } = await supabase
      .rpc('check_bsl_eligibility', { artist_id: artistId });
    
    if (eligibilityError || !eligible) {
      return res.status(403).json({ 
        error: 'Artist not eligible for BSL licensing' 
      });
    }
    
    // Update content to BSL license
    const { data, error } = await supabase
      .from('content_items')
      .update({ license_type: 'bsl' })
      .eq('id', content_id)
      .eq('artist_id', artistId)
      .select()
      .single();
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json({ success: true, data });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get BSL-licensed tracks
router.get('/bsl/tracks', requireAuth, async (req: Request, res: Response) => {
  try {
    const artistId = await getArtistId(req.user.id);
    
    const { data, error } = await supabase
      .from('content_items')
      .select('*')
      .eq('artist_id', artistId)
      .eq('license_type', 'bsl')
      .order('created_at', { ascending: false });
    
    if (error) {
      return res.status(400).json({ error: error.message });
    }
    
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

export default router;