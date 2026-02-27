#!/bin/bash
# ============================================================================
# COLISEUM TEST SUITE - Complete Test Data Setup and Verification
# ============================================================================
# Purpose: Create test data, simulate plays, process, and verify rankings
# ============================================================================

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_URL="${DATABASE_URL:-}"

if [ -z "$DB_URL" ]; then
  echo -e "${RED}Error: DATABASE_URL not set${NC}"
  echo "Set DATABASE_URL or run: source .env"
  exit 1
fi

echo -e "${GREEN}🚀 Coliseum Test Suite${NC}"
echo "================================"
echo ""

# Step 1: Create test data
echo -e "${YELLOW}Step 1: Creating test artists and content...${NC}"
psql "$DB_URL" -f "$SCRIPT_DIR/create_coliseum_test_data.sql"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Test data created${NC}"
else
  echo -e "${RED}❌ Failed to create test data${NC}"
  exit 1
fi
echo ""

# Step 2: Simulate audio plays
echo -e "${YELLOW}Step 2: Simulating audio plays...${NC}"
psql "$DB_URL" -f "$SCRIPT_DIR/simulate_audio_plays.sql"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Audio plays simulated${NC}"
else
  echo -e "${RED}❌ Failed to simulate plays${NC}"
  exit 1
fi
echo ""

# Step 3: Trigger processor
echo -e "${YELLOW}Step 3: Triggering Coliseum processor...${NC}"
cd "$PROJECT_DIR"

# Get service role key
if [ -f .env ]; then
  SERVICE_KEY=$(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d '=' -f2 | tr -d '"' | tr -d "'" | xargs)
else
  echo -e "${RED}Error: .env file not found${NC}"
  exit 1
fi

if [ -z "$SERVICE_KEY" ]; then
  echo -e "${RED}Error: SUPABASE_SERVICE_ROLE_KEY not found in .env${NC}"
  exit 1
fi

RESPONSE=$(curl -s -X POST \
  "https://iutnwgvzwyupsuguxnls.supabase.co/functions/v1/coliseum-processor" \
  -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json" \
  -d '{}')

SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false')
PROCESSED=$(echo "$RESPONSE" | jq -r '.processed // 0')
MUTATIONS=$(echo "$RESPONSE" | jq -r '.mutations_generated // 0')

if [ "$SUCCESS" = "true" ]; then
  echo -e "${GREEN}✅ Processor triggered successfully${NC}"
  echo "   Events processed: $PROCESSED"
  echo "   Mutations generated: $MUTATIONS"
else
  echo -e "${RED}❌ Processor failed${NC}"
  echo "Response: $RESPONSE"
  exit 1
fi
echo ""

# Step 4: Wait for processing
echo -e "${YELLOW}Step 4: Waiting for processing to complete...${NC}"
sleep 5
echo -e "${GREEN}✅ Processing complete${NC}"
echo ""

# Step 5: Verify results
echo -e "${YELLOW}Step 5: Verifying results...${NC}"
psql "$DB_URL" -f "$SCRIPT_DIR/verify_coliseum_test_data.sql"
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✅ Verification complete${NC}"
else
  echo -e "${RED}❌ Verification failed${NC}"
  exit 1
fi
echo ""

# Step 6: Show leaderboard
echo -e "${YELLOW}Step 6: Final Leaderboard Rankings${NC}"
psql "$DB_URL" -c "
SELECT 
  ROW_NUMBER() OVER (ORDER BY domain_strength DESC) as rank,
  artist_name,
  ROUND(domain_strength, 2) as strength,
  last_updated
FROM coliseum_leaderboard_t_7d
WHERE artist_name LIKE 'Test Artist%'
ORDER BY domain_strength DESC;
"

echo ""
echo -e "${GREEN}🎉 Test Suite Complete!${NC}"
echo ""
echo "Expected Rankings:"
echo "  1. Test Artist Gamma (12 plays)"
echo "  2. Test Artist Alpha (10 plays)"
echo "  3. Test Artist Delta (7 plays)"
echo "  4. Test Artist Beta (5 plays)"
echo ""
echo "Next steps:"
echo "  1. Check /coliseum-dashboard in frontend"
echo "  2. Verify rankings match expected order"
echo "  3. Test switching between domains (A/T/G/C)"
