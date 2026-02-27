#!/bin/bash
# ============================================================================
# Complete Test Data Setup with Audio Files
# ============================================================================
# Purpose: Create test artists, upload audio files, simulate plays, process
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🎵 Complete Test Data Setup with Audio Files${NC}"
echo "=================================================="
echo ""

# Load environment variables
if [ -f .env ]; then
  export $(cat .env | grep -v '^#' | xargs)
else
  echo -e "${RED}❌ .env file not found${NC}"
  exit 1
fi

# Check DATABASE_URL
if [ -z "$DATABASE_URL" ]; then
  echo -e "${YELLOW}⚠️  DATABASE_URL not set in .env${NC}"
  echo "   Using Supabase connection string..."
  # Try to construct from SUPABASE_URL
  if [ -n "$SUPABASE_URL" ]; then
    echo "   You may need to set DATABASE_URL manually"
  fi
fi

# Step 1: Create test artists and content
echo -e "${YELLOW}Step 1: Creating test artists and content...${NC}"
if [ -z "$DATABASE_URL" ]; then
  echo -e "${RED}❌ DATABASE_URL required for SQL scripts${NC}"
  echo "   Set DATABASE_URL in .env or export it"
  exit 1
fi

psql "$DATABASE_URL" -f "$SCRIPT_DIR/create_coliseum_test_data.sql" 2>&1 | grep -v "NOTICE:" || true
echo -e "${GREEN}✅ Test data created${NC}"
echo ""

# Step 2: Upload audio files
echo -e "${YELLOW}Step 2: Uploading audio files to Supabase Storage...${NC}"
node "$SCRIPT_DIR/upload_test_audio_files.js"
UPLOAD_EXIT=$?

if [ $UPLOAD_EXIT -eq 0 ]; then
  echo -e "${GREEN}✅ Audio files uploaded${NC}"
else
  echo -e "${YELLOW}⚠️  Audio upload had issues (may continue anyway)${NC}"
fi
echo ""

# Step 3: Simulate audio plays
echo -e "${YELLOW}Step 3: Simulating audio plays...${NC}"
psql "$DATABASE_URL" -f "$SCRIPT_DIR/simulate_audio_plays.sql" 2>&1 | grep -v "NOTICE:" || true
echo -e "${GREEN}✅ Audio plays simulated${NC}"
echo ""

# Step 4: Trigger processor
echo -e "${YELLOW}Step 4: Triggering Coliseum processor...${NC}"
if [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
  echo -e "${RED}❌ SUPABASE_SERVICE_ROLE_KEY not found${NC}"
  exit 1
fi

RESPONSE=$(curl -s -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{}')

# Check response
if echo "$RESPONSE" | grep -q '"success":true'; then
  PROCESSED=$(echo "$RESPONSE" | grep -o '"processed":[0-9]*' | cut -d ':' -f2 || echo "0")
  MUTATIONS=$(echo "$RESPONSE" | grep -o '"mutations_generated":[0-9]*' | cut -d ':' -f2 || echo "0")
  echo -e "${GREEN}✅ Processor triggered successfully${NC}"
  echo "   Events processed: $PROCESSED"
  echo "   Mutations generated: $MUTATIONS"
else
  echo -e "${RED}❌ Processor failed${NC}"
  echo "$RESPONSE" | head -10
fi
echo ""

# Step 5: Wait for processing
echo -e "${YELLOW}Step 5: Waiting for processing to complete...${NC}"
sleep 3
echo -e "${GREEN}✅ Processing complete${NC}"
echo ""

# Step 6: Verify results
echo -e "${YELLOW}Step 6: Verifying results...${NC}"
psql "$DATABASE_URL" -f "$SCRIPT_DIR/verify_coliseum_test_data.sql" 2>&1 | grep -v "NOTICE:" || true
echo ""

# Step 7: Show leaderboard
echo -e "${YELLOW}Step 7: Final Leaderboard Rankings${NC}"
psql "$DATABASE_URL" -c "
SELECT 
  ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as rank,
  artist_name,
  ROUND(domain_strength, 2) as strength,
  last_updated
FROM coliseum_leaderboard_t_7d
WHERE artist_name LIKE 'Test Artist%'
ORDER BY domain_strength DESC;
" 2>&1 | grep -v "NOTICE:" || true

echo ""
echo -e "${GREEN}🎉 Test Data Setup Complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Start frontend: cd /Users/pks.ml/Desktop/93/my-app && npm start"
echo "  2. Check /catalog - should show 4 test artists with audio files"
echo "  3. Check /coliseum-dashboard - should show rankings"
echo "  4. Run E2E tests: npx playwright test tests/e2e/full-audio-flow.spec.ts"
echo ""
