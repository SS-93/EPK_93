require('dotenv').config();

const stripeMode = process.env.STRIPE_MODE || 'test';
const keyVar = stripeMode === 'live' ? 'STRIPE_SECRET_KEY_LIVE' : 'STRIPE_SECRET_KEY_TEST';
const webhookVar = stripeMode === 'live' ? 'STRIPE_WEBHOOK_SECRET_LIVE' : 'STRIPE_WEBHOOK_SECRET_TEST';

console.log('─────────────────────────────────────');
console.log('🔍 Stripe Configuration Check (Backend)');
console.log('─────────────────────────────────────');
console.log(`Mode: ${stripeMode === 'live' ? '🔴 LIVE' : '🟡 TEST'}`);
console.log(`Secret Key (${keyVar}):`, process.env[keyVar] ? `✅ ${process.env[keyVar].substring(0, 20)}...` : '❌ MISSING');
console.log(`Webhook Secret (${webhookVar}):`, process.env[webhookVar] ? `✅ ${process.env[webhookVar].substring(0, 15)}...` : '❌ MISSING');
console.log('─────────────────────────────────────');

// Additional checks
console.log('\n📋 Additional Configuration:');
console.log(`Supabase URL:`, process.env.SUPABASE_URL ? '✅ SET' : '❌ MISSING');
console.log(`Supabase Service Key:`, process.env.SUPABASE_SERVICE_ROLE_KEY ? '✅ SET' : '❌ MISSING');
console.log(`API URL:`, process.env.API_URL || 'http://localhost:8000 (default)');
console.log(`APP URL:`, process.env.APP_URL || 'http://localhost:3000 (default)');

console.log('\n─────────────────────────────────────');

// Error checking
let hasErrors = false;

if (!process.env[keyVar]) {
  console.error(`❌ ERROR: ${keyVar} not set in .env`);
  hasErrors = true;
}

if (!process.env[webhookVar]) {
  console.warn(`⚠️  WARNING: ${webhookVar} not set in .env`);
  console.warn('   Webhook events will fail signature verification');
  console.warn('   Use Stripe CLI: stripe listen --forward-to localhost:8000/stripe/webhook');
}

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  console.error('❌ ERROR: Supabase credentials missing');
  hasErrors = true;
}

console.log('─────────────────────────────────────\n');

if (hasErrors) {
  console.error('❌ Configuration has errors. Fix before running server.\n');
  process.exit(1);
} else {
  console.log('✅ Stripe configuration looks good!\n');
  console.log('Next steps:');
  console.log('1. Start backend: npm start (or node server.js)');
  console.log('2. Start frontend: cd ../93/my-app && npm start');
  console.log('3. Test checkout: http://localhost:3000/test-checkout');
  console.log('\n');
}
