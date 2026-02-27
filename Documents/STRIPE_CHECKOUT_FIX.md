# Stripe Checkout Complete Fix Guide

**Errors:**
1. ❌ Content Security Policy (CSP) blocking inline scripts
2. ❌ 401 Unauthorized from Stripe API
3. ❌ Tracking scripts blocked by ad blocker

---

## 🔍 Issue Analysis

### **Error 1: CSP Violations**
```
Executing inline script violates CSP directive 'script-src 'self' https://js.stripe.com ...'
```

**Cause:** Strict CSP policy blocking Stripe's inline scripts

---

###**Error 2: 401 Unauthorized (CRITICAL)**
```
POST https://api.stripe.com/v1/payment_pages/cs_test_.../init 401 (Unauthorized)
```

**Cause:** Checkout session created with **DIFFERENT** keys than what frontend is using!

**Example:**
- Backend creates session with: `sk_test_51RkDc9...` (Account 51RkDc9)
- Frontend tries to load with: `pk_test_51RkDby...` (Account 51RkDby) ❌ MISMATCH!

---

### **Error 3: Tracking Blocked**
```
GET https://m.stripe.network/out-4.5.45.js net::ERR_BLOCKED_BY_CLIENT
GET https://hcaptcha.com/1/api.js net::ERR_BLOCKED_BY_CLIENT
```

**Cause:** Ad blocker or privacy extension blocking Stripe analytics

---

## ✅ Solution 1: Fix Key Mismatch (Most Important!)

### **Step 1: Verify Keys Match**

Run these commands to check which keys are loaded:

**Backend:**
```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
node -e "require('dotenv').config(); const mode = process.env.STRIPE_MODE || 'test'; const key = mode === 'live' ? process.env.STRIPE_SECRET_KEY_LIVE : process.env.STRIPE_SECRET_KEY_TEST; console.log('Backend using:', key ? key.substring(7, 17) + '...' : 'MISSING');"
```

**Frontend:**
```bash
cd /Users/pks.ml/Desktop/93/my-app
node -e "require('dotenv').config({ path: '.env.local' }); const mode = process.env.REACT_APP_STRIPE_MODE || 'test'; const key = mode === 'live' ? process.env.REACT_APP_STRIPE_PUBLISHABLE_KEY_LIVE : process.env.REACT_APP_STRIPE_PUBLISHABLE_KEY_TEST; console.log('Frontend using:', key ? key.substring(8, 18) + '...' : 'MISSING');"
```

**Both should show the SAME account ID!**
- Backend: `51RkDc9FLes6...`
- Frontend: `51RkDc9FLes6...` ✅ MATCH

If they don't match:
- Backend: `51RkDc9FLes6...`
- Frontend: `51RkDbyFE3Yr...` ❌ WRONG!

---

### **Step 2: Get Matching Keys from Stripe**

1. Go to: https://dashboard.stripe.com/test/apikeys
2. Make sure you're in **TEST MODE** (toggle top-right)
3. Copy BOTH keys from the **SAME** account:
   - Publishable key: `pk_test_51...`
   - Secret key: `sk_test_51...`

**Critical:** The account ID (first 11 characters after `pk_test_` or `sk_test_`) MUST MATCH!

Example:
- ✅ `pk_test_51RkDc9FLes6...` + `sk_test_51RkDc9FLes6...` (SAME)
- ❌ `pk_test_51RkDc9FLes6...` + `sk_test_51RkDbyFE3Yr...` (DIFFERENT)

---

### **Step 3: Update Backend Keys**

Edit: `/Users/pks.ml/Desktop/EPK-93/Buckets_SB/.env`

```env
STRIPE_MODE=test

# Paste BOTH keys from the SAME Stripe account
STRIPE_SECRET_KEY_TEST=sk_test_PASTE_YOUR_KEY_HERE
STRIPE_WEBHOOK_SECRET_TEST=whsec_PASTE_WEBHOOK_SECRET_HERE
```

---

### **Step 4: Update Frontend Keys**

Edit: `/Users/pks.ml/Desktop/93/my-app/.env.local`

```env
REACT_APP_STRIPE_MODE=test

# Paste the publishable key from the SAME account as backend
REACT_APP_STRIPE_PUBLISHABLE_KEY_TEST=pk_test_PASTE_YOUR_KEY_HERE
```

---

### **Step 5: Restart BOTH Servers**

**Terminal 1 - Backend:**
```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
# Kill existing (Ctrl+C)
npm start
# OR
node server.js

# Should see: [Stripe] Initialized in 🟡 TEST mode
```

**Terminal 2 - Frontend:**
```bash
cd /Users/pks.ml/Desktop/93/my-app
# Kill existing (Ctrl+C)
npm start

# Check browser console for:
# [stripeClient] Mode: 🟡 TEST
# [stripeClient] Key: pk_test_51RkDc9... (should match backend)
```

---

## ✅ Solution 2: Fix CSP Errors

### **Option A: Disable CSP for Development (Quick)**

Add this to `public/index.html` (between `<head>` tags):

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self';
               script-src 'self' 'unsafe-inline' 'unsafe-eval' https://js.stripe.com https://m.stripe.network;
               frame-src 'self' https://js.stripe.com https://hooks.stripe.com;
               connect-src 'self' https://api.stripe.com https://m.stripe.network;
               img-src 'self' data: https:;
               style-src 'self' 'unsafe-inline';">
```

**Then restart frontend server**

---

### **Option B: Strict CSP with Nonces (Production-Ready)**

This requires updating webpack config to generate nonces. For now, use Option A for development.

---

### **Option C: Disable Browser Extensions**

If CSP errors persist:
1. Open browser in **Incognito/Private mode** (disables extensions)
2. Or disable ad blocker, privacy badger, etc.
3. Test checkout again

---

## ✅ Solution 3: Fix Ad Blocker Issues

The errors:
```
GET https://m.stripe.network/out-4.5.45.js net::ERR_BLOCKED_BY_CLIENT
```

These are **non-critical** (Stripe analytics/fraud detection), but can cause issues.

**Fix:**
1. Disable ad blocker for `localhost:3000`
2. Or whitelist `*.stripe.com`, `*.stripe.network`
3. Or test in incognito mode

---

## 🧪 Testing the Fix

### **Test 1: Verify Keys Match**

Run both commands from Step 1 above and confirm account IDs match.

---

### **Test 2: Test Checkout Session Creation**

**Option A: Via curl:**
```bash
curl -X POST http://localhost:8000/stripe/create-checkout-session \
  -H "Content-Type: application/json" \
  -d '{
    "productType": "ticket",
    "amountCents": 2000,
    "userId": "test-user-123",
    "customerEmail": "test@example.com"
  }'
```

**Expected response:**
```json
{
  "sessionId": "cs_test_...",
  "url": "https://checkout.stripe.com/c/pay/cs_test_..."
}
```

**If you get an error:** Check backend logs and Stripe keys

---

### **Test 3: Test Checkout Page**

1. Go to: http://localhost:3000/test-checkout
2. Click "Proceed to Checkout"
3. Should see Stripe Checkout page load (no CSP errors)
4. Use test card: `4242 4242 4242 4242`
5. Payment should succeed

---

### **Test 4: Check Browser Console**

**Should see:**
```
[stripeClient] Mode: 🟡 TEST
[stripeClient] Key: pk_test_51RkDc9...
[useStripeCheckout] Running in 🟡 TEST mode
[useStripeCheckout] API URL: http://localhost:8000
```

**Should NOT see:**
- ❌ CSP violation errors
- ❌ 401 Unauthorized from Stripe
- ❌ "Stripe publishable key not configured"

---

## 🔧 Advanced Troubleshooting

### **Issue: Still getting 401 Unauthorized**

**Possible causes:**
1. Keys still don't match (recheck!)
2. Checkout session expired (sessions expire after 24h)
3. Wrong Stripe account (check dashboard)

**Debug:**
```bash
# Check which Stripe account you're logged into
# https://dashboard.stripe.com/settings/user

# Verify session was created with correct account
# In backend logs, should see:
# [Stripe] Creating checkout session: ...
```

---

### **Issue: CSP errors persist**

**Try:**
1. Hard refresh browser: `Cmd+Shift+R` (Mac) or `Ctrl+Shift+R` (Windows)
2. Clear browser cache
3. Test in incognito mode
4. Check if CSP is coming from network (corporate proxy)

---

### **Issue: Checkout page loads but payment fails**

**Check:**
1. Test card number correct: `4242 4242 4242 4242`
2. Webhook configured (for fulfillment)
3. Backend logs for errors
4. Database for purchase record

---

## ✅ Complete Checklist

**Environment Variables:**
- [ ] Backend `.env`: `STRIPE_MODE=test`
- [ ] Backend `.env`: `STRIPE_SECRET_KEY_TEST` set
- [ ] Frontend `.env.local`: `REACT_APP_STRIPE_MODE=test`
- [ ] Frontend `.env.local`: `REACT_APP_STRIPE_PUBLISHABLE_KEY_TEST` set
- [ ] **Keys from SAME Stripe account** (account IDs match)

**Servers:**
- [ ] Backend running: http://localhost:8000
- [ ] Frontend running: http://localhost:3000
- [ ] Both restarted after .env changes

**Browser:**
- [ ] CSP fixed (Option A meta tag added, OR incognito mode)
- [ ] Ad blocker disabled or whitelisted
- [ ] Hard refresh done

**Testing:**
- [ ] Verification scripts show matching keys
- [ ] Can create checkout session via curl
- [ ] Checkout page loads without CSP errors
- [ ] No 401 errors in console
- [ ] Test payment succeeds

---

## 🎯 Quick Fix Script

Create: `test-stripe-checkout.sh`

```bash
#!/bin/bash

echo "🧪 Testing Stripe Checkout..."
echo ""

# Test 1: Verify backend
echo "1️⃣ Testing backend endpoint..."
RESPONSE=$(curl -s -X POST http://localhost:8000/stripe/create-checkout-session \
  -H "Content-Type: application/json" \
  -d '{
    "productType": "ticket",
    "amountCents": 2000,
    "userId": "test-user-123",
    "customerEmail": "test@example.com"
  }')

if echo "$RESPONSE" | grep -q "sessionId"; then
  echo "✅ Backend OK - Session created"
  echo "$RESPONSE" | grep -o '"sessionId":"[^"]*"'
else
  echo "❌ Backend ERROR"
  echo "$RESPONSE"
  exit 1
fi

echo ""
echo "2️⃣ Open test checkout page:"
echo "http://localhost:3000/test-checkout"
echo ""
echo "3️⃣ Use test card: 4242 4242 4242 4242"
echo ""
```

**Make executable and run:**
```bash
chmod +x test-stripe-checkout.sh
./test-stripe-checkout.sh
```

---

## 📞 Still Having Issues?

### **Debug Checklist:**

1. **Run verification scripts:**
   ```bash
   cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
   node verify-stripe.js
   ```

2. **Check browser console** for specific errors

3. **Check backend logs** for Stripe initialization message

4. **Verify Stripe dashboard** shows test mode and correct keys

5. **Try incognito mode** to rule out extensions

6. **Check network tab** in devtools for failed requests

---

## ✅ Success Criteria

**Checkout is working when:**
- ✅ No CSP errors in console
- ✅ No 401 errors from Stripe API
- ✅ Checkout page loads and shows payment form
- ✅ Test card payment succeeds
- ✅ Success page displays after payment
- ✅ Purchase/ticket created in database

---

**Most likely fix:** Update keys to match between backend and frontend, then restart both servers! 🚀
