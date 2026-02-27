#!/bin/bash

echo "🧪 Testing Stripe Checkout Configuration..."
echo ""

# Test 1: Verify backend running
echo "1️⃣ Checking if backend is running..."
if curl -s http://localhost:8000 > /dev/null; then
  echo "✅ Backend is running on http://localhost:8000"
else
  echo "❌ Backend is NOT running!"
  echo "   Start with: npm start OR node server.js"
  exit 1
fi

echo ""

# Test 2: Verify frontend running
echo "2️⃣ Checking if frontend is running..."
if curl -s http://localhost:3000 > /dev/null; then
  echo "✅ Frontend is running on http://localhost:3000"
else
  echo "❌ Frontend is NOT running!"
  echo "   Start with: cd /Users/pks.ml/Desktop/93/my-app && npm start"
  exit 1
fi

echo ""

# Test 3: Create test checkout session
echo "3️⃣ Creating test checkout session..."
RESPONSE=$(curl -s -X POST http://localhost:8000/stripe/create-checkout-session \
  -H "Content-Type: application/json" \
  -d '{
    "productType": "ticket",
    "amountCents": 2000,
    "userId": "test-user-123",
    "customerEmail": "test@example.com"
  }')

if echo "$RESPONSE" | grep -q "sessionId"; then
  echo "✅ Checkout session created successfully!"
  echo ""
  SESSION_ID=$(echo "$RESPONSE" | grep -o '"sessionId":"cs_test_[^"]*"' | cut -d'"' -f4)
  echo "   Session ID: $SESSION_ID"
  echo ""
else
  echo "❌ Failed to create checkout session!"
  echo ""
  echo "Response:"
  echo "$RESPONSE"
  echo ""
  echo "Check backend logs for errors"
  exit 1
fi

# Test 4: Instructions
echo "──────────────────────────────────────"
echo "✅ All checks passed!"
echo "──────────────────────────────────────"
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Open test checkout page:"
echo "   http://localhost:3000/test-checkout"
echo ""
echo "2. Click 'Proceed to Checkout'"
echo ""
echo "3. Use Stripe test card:"
echo "   Card: 4242 4242 4242 4242"
echo "   Exp: 12/34 (any future date)"
echo "   CVC: 123 (any 3 digits)"
echo "   ZIP: 12345 (any 5 digits)"
echo ""
echo "4. Complete payment and verify:"
echo "   • Success page displays"
echo "   • Purchase record created"
echo "   • Ticket generated"
echo ""
echo "──────────────────────────────────────"
echo "💡 Tip: Open browser console (F12) to see Stripe logs"
echo "──────────────────────────────────────"
