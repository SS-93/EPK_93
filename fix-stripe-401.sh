#!/bin/bash

echo "🔧 Fixing Stripe 401 Unauthorized Error..."
echo ""

# Step 1: Verify keys match
echo "1️⃣ Verifying Stripe keys match..."
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
BACKEND_ACCOUNT=$(node -e "require('dotenv').config(); const k = process.env.STRIPE_SECRET_KEY_TEST; console.log(k ? k.substring(8,19) : 'MISSING');")

cd /Users/pks.ml/Desktop/93/my-app
FRONTEND_ACCOUNT=$(node -e "require('dotenv').config({path:'.env.local'}); const k = process.env.REACT_APP_STRIPE_PUBLISHABLE_KEY_TEST; console.log(k ? k.substring(8,19) : 'MISSING');")

echo "   Backend Account:  $BACKEND_ACCOUNT"
echo "   Frontend Account: $FRONTEND_ACCOUNT"

if [ "$BACKEND_ACCOUNT" = "$FRONTEND_ACCOUNT" ]; then
  echo "   ✅ Keys match!"
else
  echo "   ❌ Keys DON'T match! Fix your .env files first."
  exit 1
fi

echo ""

# Step 2: Check if servers need restart
echo "2️⃣ Checking server status..."

# Check backend
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
BACKEND_PID=$(ps aux | grep "node server.js" | grep -v grep | awk '{print $2}' | head -1)

if [ -z "$BACKEND_PID" ]; then
  echo "   ❌ Backend NOT running!"
  echo "   Start with: node server.js"
  exit 1
else
  echo "   ✅ Backend running (PID: $BACKEND_PID)"
fi

# Check frontend
FRONTEND_PID=$(ps aux | grep "react-scripts/scripts/start.js" | grep -v grep | awk '{print $2}' | head -1)

if [ -z "$FRONTEND_PID" ]; then
  echo "   ❌ Frontend NOT running!"
  echo "   Start with: cd /Users/pks.ml/Desktop/93/my-app && npm start"
  exit 1
else
  echo "   ✅ Frontend running (PID: $FRONTEND_PID)"
fi

echo ""

# Step 3: Offer to restart frontend
echo "3️⃣ Frontend needs restart to pick up new keys and CSP..."
echo ""
read -p "   Restart frontend now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "   🔄 Killing frontend (PID: $FRONTEND_PID)..."
  kill $FRONTEND_PID
  sleep 2

  echo "   🚀 Starting frontend..."
  cd /Users/pks.ml/Desktop/93/my-app
  npm start &

  echo ""
  echo "   ✅ Frontend restarting..."
  echo "   Wait 10-15 seconds for it to fully start"
  echo ""
else
  echo ""
  echo "   ⚠️  Manual restart required:"
  echo "   1. Go to terminal running 'npm start'"
  echo "   2. Press Ctrl+C"
  echo "   3. Run: npm start"
  echo ""
  exit 0
fi

echo ""
echo "──────────────────────────────────────"
echo "✅ Fix applied!"
echo "──────────────────────────────────────"
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Wait for frontend to fully start (watch for 'webpack compiled')"
echo ""
echo "2. Open browser and HARD REFRESH:"
echo "   • Mac: Cmd+Shift+R"
echo "   • Windows: Ctrl+Shift+R"
echo ""
echo "3. Go to: http://localhost:3000/test-checkout"
echo ""
echo "4. Click 'Proceed to Checkout'"
echo ""
echo "5. Should now work without 401 errors!"
echo ""
echo "──────────────────────────────────────"
echo "💡 Still seeing errors?"
echo ""
echo "• Try incognito mode (disables extensions)"
echo "• Check browser console for specific error"
echo "• Verify you hard refreshed (Cmd+Shift+R)"
echo ""
