/**
 * Create Test Data via Supabase REST API
 * Uses Supabase JS client instead of direct psql connection
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

/**
 * Create test artists
 */
async function createTestArtists() {
  console.log('📋 Creating test artists...');
  
  const artists = [
    {
      artist_name: 'Test Artist Alpha',
      bio: 'Electronic dance music producer specializing in progressive house',
      verification_status: 'verified'
    },
    {
      artist_name: 'Test Artist Beta',
      bio: 'Indie rock band with folk influences',
      verification_status: 'verified'
    },
    {
      artist_name: 'Test Artist Gamma',
      bio: 'Hip-hop artist from the West Coast',
      verification_status: 'verified'
    },
    {
      artist_name: 'Test Artist Delta',
      bio: 'Jazz fusion pianist and composer',
      verification_status: 'verified'
    }
  ];
  
  const createdArtists = [];
  
  for (const artist of artists) {
    // Check if exists
    const { data: existing } = await supabase
      .from('artist_profiles')
      .select('id')
      .eq('artist_name', artist.artist_name)
      .single();
    
    if (existing) {
      console.log(`   ⚠️  ${artist.artist_name} already exists`);
      createdArtists.push({ id: existing.id, ...artist });
      continue;
    }
    
    // Create artist
    const { data, error } = await supabase
      .from('artist_profiles')
      .insert(artist)
      .select()
      .single();
    
    if (error) {
      console.error(`   ❌ Error creating ${artist.artist_name}:`, error.message);
      continue;
    }
    
    console.log(`   ✅ Created: ${artist.artist_name} (${data.id})`);
    createdArtists.push(data);
  }
  
  return createdArtists;
}

/**
 * Create test content for an artist
 */
async function createTestContent(artistId, artistName, genre, tracks) {
  console.log(`📝 Creating content for ${artistName}...`);
  
  const createdTracks = [];
  
  for (const track of tracks) {
    const { data, error } = await supabase
      .from('content_items')
      .insert({
        artist_id: artistId,
        title: track.title,
        description: track.description,
        content_type: 'audio',
        file_path: track.file_path || `https://example.com/audio/${track.title.toLowerCase().replace(/\s+/g, '-')}.mp3`,
        duration_seconds: track.duration,
        is_published: true,
        metadata: {
          genre,
          subgenre: track.subgenre,
          bpm: track.bpm,
          artist_genres: track.genres || []
        }
      })
      .select()
      .single();
    
    if (error) {
      console.error(`   ❌ Error creating ${track.title}:`, error.message);
      continue;
    }
    
    console.log(`   ✅ Created: ${track.title}`);
    createdTracks.push(data);
  }
  
  return createdTracks;
}

/**
 * Main function
 */
async function main() {
  console.log('🎵 Creating Test Data via Supabase API');
  console.log('======================================\n');
  
  try {
    // Step 1: Create artists
    const artists = await createTestArtists();
    console.log('');
    
    if (artists.length === 0) {
      console.error('❌ No artists created');
      process.exit(1);
    }
    
    // Step 2: Create content for each artist
    const contentMap = {
      'Test Artist Alpha': [
        { title: 'Alpha Track 1 - Midnight Pulse', description: 'High-energy progressive house track', duration: 240, subgenre: 'Progressive House', bpm: 128, genres: ['Electronic', 'House', 'Dance'] },
        { title: 'Alpha Track 2 - Neon Dreams', description: 'Synthwave-inspired electronic track', duration: 210, subgenre: 'Synthwave', bpm: 120, genres: ['Electronic', 'Synthwave', 'Retro'] },
        { title: 'Alpha Track 3 - Digital Horizon', description: 'Ambient electronic soundscape', duration: 300, subgenre: 'Ambient', bpm: 90, genres: ['Electronic', 'Ambient', 'Chill'] },
        { title: 'Alpha Track 4 - Electric Storm', description: 'High-energy EDM banger', duration: 195, subgenre: 'EDM', bpm: 140, genres: ['Electronic', 'EDM', 'Festival'] }
      ],
      'Test Artist Beta': [
        { title: 'Beta Track 1 - Mountain View', description: 'Acoustic indie folk ballad', duration: 245, subgenre: 'Folk', bpm: 85, genres: ['Indie', 'Folk', 'Acoustic'] },
        { title: 'Beta Track 2 - City Lights', description: 'Upbeat indie rock anthem', duration: 220, subgenre: 'Rock', bpm: 110, genres: ['Indie', 'Rock', 'Alternative'] },
        { title: 'Beta Track 3 - Sunset Drive', description: 'Dreamy indie pop track', duration: 195, subgenre: 'Pop', bpm: 100, genres: ['Indie', 'Pop', 'Dream Pop'] },
        { title: 'Beta Track 4 - Wildfire', description: 'Energetic indie rock song', duration: 230, subgenre: 'Rock', bpm: 115, genres: ['Indie', 'Rock', 'Garage Rock'] }
      ],
      'Test Artist Gamma': [
        { title: 'Gamma Track 1 - West Coast Flow', description: 'Classic West Coast hip-hop', duration: 210, subgenre: 'West Coast', bpm: 95, genres: ['Hip-Hop', 'Rap', 'West Coast'] },
        { title: 'Gamma Track 2 - Street Dreams', description: 'Hard-hitting trap beat', duration: 185, subgenre: 'Trap', bpm: 140, genres: ['Hip-Hop', 'Trap', 'Rap'] },
        { title: 'Gamma Track 3 - Midnight Sessions', description: 'Smooth R&B influenced hip-hop', duration: 225, subgenre: 'R&B', bpm: 90, genres: ['Hip-Hop', 'R&B', 'Soul'] },
        { title: 'Gamma Track 4 - Power Move', description: 'Aggressive rap track', duration: 200, subgenre: 'Rap', bpm: 100, genres: ['Hip-Hop', 'Rap', 'Hardcore'] }
      ],
      'Test Artist Delta': [
        { title: 'Delta Track 1 - Blue Notes', description: 'Smooth jazz piano composition', duration: 320, subgenre: 'Smooth Jazz', bpm: 70, genres: ['Jazz', 'Smooth Jazz', 'Piano'] },
        { title: 'Delta Track 2 - Fusion Groove', description: 'Jazz fusion with modern elements', duration: 280, subgenre: 'Fusion', bpm: 110, genres: ['Jazz', 'Fusion', 'Progressive'] },
        { title: 'Delta Track 3 - Midnight Swing', description: 'Classic swing jazz', duration: 195, subgenre: 'Swing', bpm: 180, genres: ['Jazz', 'Swing', 'Big Band'] },
        { title: 'Delta Track 4 - Modern Standards', description: 'Contemporary jazz interpretation', duration: 265, subgenre: 'Contemporary', bpm: 85, genres: ['Jazz', 'Contemporary', 'Modern'] }
      ]
    };
    
    const genreMap = {
      'Test Artist Alpha': 'Electronic',
      'Test Artist Beta': 'Indie',
      'Test Artist Gamma': 'Hip-Hop',
      'Test Artist Delta': 'Jazz'
    };
    
    for (const artist of artists) {
      const tracks = contentMap[artist.artist_name] || [];
      const genre = genreMap[artist.artist_name] || 'Unknown';
      
      await createTestContent(artist.id, artist.artist_name, genre, tracks);
      console.log('');
    }
    
    console.log('✅ Test data creation complete!');
    console.log('\n📊 Summary:');
    console.log(`   Artists created: ${artists.length}`);
    console.log(`   Total tracks: ${artists.length * 4}`);
    console.log('\n🎯 Next steps:');
    console.log('   1. Upload audio files: node scripts/upload_test_audio_files.js');
    console.log('   2. Simulate plays: Run simulate_audio_plays.sql');
    console.log('   3. Trigger processor');
    
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { createTestArtists, createTestContent };
