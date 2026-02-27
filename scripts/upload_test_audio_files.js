/**
 * Upload Test Audio Files to Supabase Storage
 * 
 * Purpose: Upload test audio files and assign them to test artists
 * Usage: node scripts/upload_test_audio_files.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

// Get credentials from environment
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('❌ Missing Supabase credentials in .env file');
  console.error('   Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// Test audio files from frontend directory
const TEST_AUDIO_DIR = '/Users/pks.ml/Desktop/93/my-app/Test-Audio';
const AUDIO_FILES = [
  'akuma-new-jazz-type-beat_TK16053830.mp3.mp3',
  'free-selfish-acoustic-sza-x-her-type-beat_TK14845480.mp3.mp3',
  'free-soul-acoustic-sza-x-jhene-aiko-type-beat_TK15547357.mp3.mp3',
  'free-timing-acoustic-sza-x-her-type-beat_TK14920459.mp3.mp3'
];

// Storage bucket name (adjust if different)
const STORAGE_BUCKET = 'audio'; // or 'content' or 'tracks' - check your Supabase storage

/**
 * Find available storage bucket
 */
async function findStorageBucket() {
  const commonBuckets = ['audio', 'content', 'tracks', 'media', 'files'];
  
  for (const bucket of commonBuckets) {
    try {
      const { data, error } = await supabase.storage.from(bucket).list('', { limit: 1 });
      if (!error) {
        console.log(`✅ Found storage bucket: ${bucket}`);
        return bucket;
      }
    } catch (err) {
      // Try next bucket
    }
  }
  
  console.log(`⚠️  Could not find storage bucket. Using default: ${STORAGE_BUCKET}`);
  return STORAGE_BUCKET;
}

/**
 * Upload file to Supabase Storage
 */
async function uploadFile(filePath, fileName, artistName, bucketName) {
  try {
    console.log(`📤 Uploading ${fileName} for ${artistName}...`);
    
    // Read file
    const fileBuffer = fs.readFileSync(filePath);
    
    // Create storage path: test-artists/{artist-name}/{filename}
    const storagePath = `test-artists/${artistName.toLowerCase().replace(/\s+/g, '-')}/${fileName}`;
    
    // Upload to Supabase Storage
    const { data, error } = await supabase.storage
      .from(bucketName)
      .upload(storagePath, fileBuffer, {
        contentType: 'audio/mpeg',
        upsert: true // Overwrite if exists
      });
    
    if (error) {
      console.error(`❌ Error uploading ${fileName}:`, error);
      return null;
    }
    
    // Get public URL
    const { data: urlData } = supabase.storage
      .from(bucketName)
      .getPublicUrl(storagePath);
    
    console.log(`✅ Uploaded: ${urlData.publicUrl}`);
    return urlData.publicUrl;
  } catch (error) {
    console.error(`❌ Error uploading ${fileName}:`, error.message);
    return null;
  }
}

/**
 * Get test artists from database
 */
async function getTestArtists() {
  const { data, error } = await supabase
    .from('artist_profiles')
    .select('id, artist_name')
    .like('artist_name', 'Test Artist%')
    .order('artist_name');
  
  if (error) {
    console.error('❌ Error fetching artists:', error);
    return [];
  }
  
  return data || [];
}

/**
 * Update content_items with actual file URLs
 */
async function updateContentItem(contentId, fileUrl) {
  const { error } = await supabase
    .from('content_items')
    .update({
      file_path: fileUrl,
      file_url: fileUrl // Some schemas use file_url instead
    })
    .eq('id', contentId);
  
  if (error) {
    console.error(`❌ Error updating content item ${contentId}:`, error);
    return false;
  }
  
  return true;
}

/**
 * Main function
 */
async function main() {
  console.log('🎵 Uploading Test Audio Files to Supabase Storage');
  console.log('================================================\n');
  
  // Check if audio directory exists
  if (!fs.existsSync(TEST_AUDIO_DIR)) {
    console.error(`❌ Audio directory not found: ${TEST_AUDIO_DIR}`);
    process.exit(1);
  }
  
  // Get test artists
  console.log('📋 Fetching test artists...');
  const artists = await getTestArtists();
  
  if (artists.length === 0) {
    console.log('⚠️  No test artists found. Creating them first...');
    console.log('   Run: psql $DATABASE_URL -f scripts/create_coliseum_test_data.sql');
    process.exit(1);
  }
  
  console.log(`✅ Found ${artists.length} test artists:\n`);
  artists.forEach((artist, i) => {
    console.log(`   ${i + 1}. ${artist.artist_name} (${artist.id})`);
  });
  console.log('');
  
  // Find storage bucket
  console.log('🔍 Finding storage bucket...');
  const bucketName = await findStorageBucket();
  console.log('');
  
  // Upload files and assign to artists (round-robin)
  const uploadedFiles = [];
  
  for (let i = 0; i < AUDIO_FILES.length; i++) {
    const fileName = AUDIO_FILES[i];
    const filePath = path.join(TEST_AUDIO_DIR, fileName);
    
    // Check if file exists
    if (!fs.existsSync(filePath)) {
      console.log(`⚠️  File not found: ${filePath}`);
      continue;
    }
    
    // Assign to artist (round-robin)
    const artistIndex = i % artists.length;
    const artist = artists[artistIndex];
    
    // Upload file
    const fileUrl = await uploadFile(filePath, fileName, artist.artist_name, bucketName);
    
    if (fileUrl) {
      uploadedFiles.push({
        fileName,
        artistId: artist.id,
        artistName: artist.artist_name,
        fileUrl
      });
    }
    
    // Small delay between uploads
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  
  console.log('\n📝 Updating content_items with file URLs...\n');
  
  // Update content_items for each artist
  // Assign one file per artist to their first track
  for (let i = 0; i < uploadedFiles.length; i++) {
    const uploaded = uploadedFiles[i];
    
    // Get content items for this artist
    const { data: contentItems, error } = await supabase
      .from('content_items')
      .select('id, title')
      .eq('artist_id', uploaded.artistId)
      .like('title', '%Track%')
      .order('created_at')
      .limit(4);
    
    if (error) {
      console.error(`❌ Error fetching content for ${uploaded.artistName}:`, error);
      continue;
    }
    
    if (!contentItems || contentItems.length === 0) {
      console.log(`⚠️  No content items found for ${uploaded.artistName}`);
      continue;
    }
    
    // Update the first track (Track 1) with the uploaded file
    const contentItem = contentItems[0]; // First track gets the uploaded file
    const updated = await updateContentItem(contentItem.id, uploaded.fileUrl);
    
    if (updated) {
      console.log(`✅ Updated: ${contentItem.title} → ${uploaded.fileName}`);
    }
    
    // Optionally update other tracks with placeholder or same file for testing
    // For now, just update the first track per artist
  }
  
  console.log('\n✅ Upload complete!');
  console.log('\n📊 Summary:');
  uploadedFiles.forEach((file, i) => {
    console.log(`   ${i + 1}. ${file.fileName}`);
    console.log(`      Artist: ${file.artistName}`);
    console.log(`      URL: ${file.fileUrl}\n`);
  });
  
  console.log('🎯 Next steps:');
  console.log('   1. Verify files in Supabase Storage dashboard');
  console.log('   2. Check content_items have file_path/file_url updated');
  console.log('   3. Test playing tracks in frontend');
}

// Run if called directly
if (require.main === module) {
  main().catch(console.error);
}

module.exports = { uploadFile, getTestArtists, updateContentItem };
