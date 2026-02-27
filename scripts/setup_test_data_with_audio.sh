#!/bin/bash
# ============================================================================
# Complete Test Data Setup with Audio Files
# ============================================================================
# Purpose: Create test artists, upload audio files, and assign them
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🎵 Setting Up Test Data with Audio Files${NC}"
echo "=============================================="
echo ""

# Step 1: Create test artists and content
echo -e "${YELLOW}Step 1: Creating test artists and content...${NC}"
if [ -z "$DATABASE_URL" ]; then
  echo -e "${RED}Error: DATABASE_URL not set${NC}"
  echo "Set DATABASE_URL or source .env file"
  exit 1
fi

psql "$DATABASE_URL" -f "$SCRIPT_DIR/create_coliseum_test_data.sql"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Test data created${NC}"
else
  echo -e "${RED}❌ Failed to create test data${NC}"
  exit 1
fi
echo ""

# Step 2: Upload audio files
echo -e "${YELLOW}Step 2: Uploading audio files to Supabase Storage...${NC}"
node "$SCRIPT_DIR/upload_test_audio_files.js"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Audio files uploaded${NC}"
else
  echo -e "${RED}❌ Failed to upload audio files${NC}"
  echo "Continuing anyway..."
fi
echo ""

# Step 3: Simulate audio plays
echo -e "${YELLOW}Step 3: Simulating audio plays...${NC}"
psql "$DATABASE_URL" -f "$SCRIPT_DIR/simulate_audio_plays.sql"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Audio plays simulated${NC}"
else
  echo -e "${RED}❌ Failed to simulate plays${NC}"
  exit 1
fi
echo ""

# Step 4: Trigger processor
echo -e "${YELLOW}Step 4: Triggering Coliseum processor...${NC}"
SERVICE_KEY=$(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" | xargs)

if [ -z "$SERVICE_KEY" ]; then
  echo -e "${RED}Error: SUPABASE_SERVICE_ROLE_KEY not found${NC}"
  exit 1
fi

RESPONSE=$(curl -s -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json" \
  -d '{}')

SUCCESS=$(echo "$RESPONSE" | grep -o '"success":[^,]*' | cut -d ':' -f2 || echo "false")

if [ "$SUCCESS" = "true" ]; then
  echo -e "${GREEN}✅ Processor triggered successfully${NC}"
  echo "$RESPONSE" | head -5
else
  echo -e "${RED}❌ Processor failed${NC}"
  echo "$RESPONSE"
fi
echo ""

# Step 5: Verify results
echo -e "${YELLOW}Step 5: Verifying results...${NC}"
psql "$DATABASE_URL" -f "$SCRIPT_DIR/verify_coliseum_test_data.sql"
echo ""

echo -e "${GREEN}🎉 Test Data Setup Complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Check /catalog in frontend - should show 4 test artists"
echo "  2. Check /coliseum-dashboard - should show rankings"
echo "  3. Play tracks to verify audio files work"
