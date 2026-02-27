# Stripe 401 Unauthorized - Quick Fix

**Error:** `POST https://api.stripe.com/v1/payment_pages/cs_test_.../init 401 (Unauthorized)`

**Root Cause:** Frontend using **old/cached** Stripe keys that don't match the backend

---

## ✅ Quick Fix (5 minutes)

### **Step 1: Verify Keys Match**

Run this to check:
```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
./fix-stripe-401.sh
```

This will:
1. Verify backend and frontend keys match
2. Check server status
3. Offer to restart frontend automatically

---

### **Step 2: Manual Restart (If Needed)**

**Backend restart:**
```bash
# In terminal running backend:
Ctrl+C

# Restart:
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
node server.js

# Should see: [Stripe] Initialized in 🟡 TEST mode
```

**Frontend restart:**
```bash
# In terminal running frontend:
Ctrl+C

# Restart:
cd /Users/pks.ml/Desktop/93/my-app
npm start

# Wait for: "webpack compiled successfully"
```

---

### **Step 3: Hard Refresh Browser**

**Critical!** You MUST hard refresh to clear cached keys:

- **Mac:** `Cmd+Shift+R`
- **Windows:** `Ctrl+Shift+R`
- **Or:** Open DevTools (F12) → Right-click refresh → "Empty Cache and Hard Reload"

---

### **Step 4: Test Checkout**

1. Go to: http://localhost:3000/test-checkout
2. Click "Proceed to Checkout"
3. Should load without 401 errors!
4. Use test card: `4242 4242 4242 4242`

---

## 🔍 Why This Happens

The 401 error occurs when:

1. **Frontend loads old keys from cache**
   - Even after updating `.env.local`, React caches the old keys
   - Hard refresh is required

2. **Servers not restarted after key changes**
   - Backend creates session with Account A
   - Frontend tries to load with Account B
   - Stripe rejects (401)

3. **Browser extension interference**
   - Ad blockers can cause issues
   - Try incognito mode if problems persist

---

## ✅ Verification

**After fix, you should see in browser console:**

```
[stripeClient] Mode: 🟡 TEST
[stripeClient] Key: pk_test_51T1LvlF34C...
[useStripeCheckout] Running in 🟡 TEST mode
```

**And NO:**
- ❌ CSP violation errors
- ❌ 401 Unauthorized errors
- ❌ "Stripe key not configured" errors

---

## 🚨 Still Not Working?

### **Check 1: Keys Actually Match**

```bash
# Backend key account
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
grep STRIPE_SECRET_KEY_TEST .env | cut -d'_' -f4 | cut -c1-11

# Frontend key account
cd /Users/pks.ml/Desktop/93/my-app
grep REACT_APP_STRIPE_PUBLISHABLE_KEY_TEST .env.local | cut -d'_' -f4 | cut -c1-11

# These MUST be identical!
```

---

### **Check 2: Get Fresh Keys from Stripe**

If keys don't match, get new ones from **the same account**:

1. Go to: https://dashboard.stripe.com/test/apikeys
2. Make sure **TEST MODE** toggle is ON (top-right)
3. Copy BOTH keys:
   - Publishable: `pk_test_51...`
   - Secret: `sk_test_51...`

4. Update backend:
```bash
# Edit /Users/pks.ml/Desktop/EPK-93/Buckets_SB/.env
STRIPE_SECRET_KEY_TEST=sk_test_PASTE_HERE
```

5. Update frontend:
```bash
# Edit /Users/pks.ml/Desktop/93/my-app/.env.local
REACT_APP_STRIPE_PUBLISHABLE_KEY_TEST=pk_test_PASTE_HERE
```

6. Restart BOTH servers
7. Hard refresh browser

---

### **Check 3: Try Incognito Mode**

This rules out extensions:
1. Open new incognito/private window
2. Go to http://localhost:3000/test-checkout
3. Test checkout

If works in incognito → disable browser extensions

---

### **Check 4: Check Server Logs**

**Backend should show:**
```
[Stripe] Initialized in 🟡 TEST mode
[Stripe] Creating checkout session: ...
```

**Frontend console should show:**
```
[stripeClient] Mode: 🟡 TEST
[stripeClient] Key: pk_test_51T1LvlF34C...
```

If not, servers didn't restart properly.

---

## 📞 Debug Commands

**Test session creation:**
```bash
curl -X POST http://localhost:8000/stripe/create-checkout-session \
  -H "Content-Type: application/json" \
  -d '{"productType":"ticket","amountCents":2000,"userId":"test","customerEmail":"test@example.com"}'

# Should return: {"sessionId":"cs_test_...","url":"https://..."}
```

**Check which keys are loaded:**
```bash
# Backend
node -e "require('dotenv').config(); console.log(process.env.STRIPE_SECRET_KEY_TEST?.substring(0,20))"

# Frontend
cd /Users/pks.ml/Desktop/93/my-app
node -e "require('dotenv').config({path:'.env.local'}); console.log(process.env.REACT_APP_STRIPE_PUBLISHABLE_KEY_TEST?.substring(0,20))"
```

---

## ✅ Success Checklist

- [ ] Backend restarted after key change
- [ ] Frontend restarted after key change
- [ ] Browser hard refreshed (Cmd+Shift+R)
- [ ] Keys verified to match (same account ID)
- [ ] No 401 errors in console
- [ ] Checkout page loads
- [ ] Test payment succeeds

---

## 🎯 The Fix in One Command

```bash
cd /Users/pks.ml/Desktop/EPK-93/Buckets_SB
./fix-stripe-401.sh
```

Then hard refresh browser: `Cmd+Shift+R`

---

**Most likely fix:** Restart frontend + hard refresh browser! 🚀
