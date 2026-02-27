#!/bin/bash
# Helper script to construct DATABASE_URL
# Get password from Supabase Dashboard → Settings → Database → Connection String

echo "To get DATABASE_URL:"
echo ""
echo "1. Go to: https://supabase.com/dashboard/project/iutnwgvzwyupsuguxnls/settings/database"
echo "2. Find 'Connection String' section"
echo "3. Copy the 'URI' connection string"
echo "4. It should look like:"
echo "   postgresql://postgres.[PROJECT-REF]:[PASSWORD]@aws-0-us-east-2.pooler.supabase.com:6543/postgres"
echo ""
echo "OR use Connection Pooling (recommended):"
echo "   postgresql://postgres.[PROJECT-REF]:[PASSWORD]@aws-0-us-east-2.pooler.supabase.com:6543/postgres"
echo ""
echo "Then export it:"
echo "   export DATABASE_URL='postgresql://...'"
echo ""
echo "Or add to .env file:"
echo "   DATABASE_URL='postgresql://...'"
