# Environment Setup Guide

## Required Environment Variables

Create a `.env` file in the root of both the frontend (`93/my-app/`) and backend (`Buckets_SB/`) directories with the following variables:

### Frontend Environment Variables (`93/my-app/.env.local`)

```bash
# Supabase Configuration
REACT_APP_SUPABASE_URL=https://your-project.supabase.co
REACT_APP_SUPABASE_ANON_KEY=your-anon-key-here

# Stripe Configuration
REACT_APP_STRIPE_PUBLISHABLE_KEY=pk_test_your-stripe-publishable-key

# Application Configuration
REACT_APP_APP_URL=http://localhost:3000
REACT_APP_API_URL=http://localhost:54321
REACT_APP_ENVIRONMENT=development

# Analytics Configuration
REACT_APP_GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX
REACT_APP_MIXPANEL_TOKEN=your-mixpanel-token

# File Upload Configuration
REACT_APP_MAX_FILE_SIZE=52428800
REACT_APP_ALLOWED_FILE_TYPES=audio/mpeg,audio/wav,video/mp4,image/jpeg,image/png,image/gif

# Development/Testing
REACT_APP_DEBUG_MODE=true
REACT_APP_ENABLE_LOGGING=true
```

### Backend Environment Variables (`Buckets_SB/.env`)

```bash
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key-here
SUPABASE_JWT_SECRET=your-jwt-secret

# Database Configuration
DATABASE_URL=postgresql://postgres:password@localhost:54322/postgres
DB_HOST=localhost
DB_PORT=54322
DB_NAME=postgres
DB_USER=postgres
DB_PASSWORD=password

# Stripe Configuration
STRIPE_SECRET_KEY=sk_test_your-stripe-secret-key
STRIPE_WEBHOOK_SECRET=whsec_your-webhook-secret

# OAuth2 Social Login Configuration
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
FACEBOOK_CLIENT_ID=your-facebook-client-id
FACEBOOK_CLIENT_SECRET=your-facebook-client-secret

# Application URLs
APP_URL=http://localhost:3000
API_URL=http://localhost:54321
CORS_ORIGINS=http://localhost:3000,https://yourdomain.com

# Security Configuration
JWT_SECRET=your-jwt-secret-key
ENCRYPTION_KEY=your-32-character-encryption-key
SESSION_SECRET=your-session-secret

# File Storage Configuration
STORAGE_BUCKET=media-uploads
MAX_FILE_SIZE=52428800
ALLOWED_FILE_TYPES=audio/mpeg,audio/wav,video/mp4,image/jpeg,image/png,image/gif

# Analytics Configuration
GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX
MIXPANEL_TOKEN=your-mixpanel-token

# Development/Testing
NODE_ENV=development
DEBUG_MODE=true
ENABLE_LOGGING=true
LOG_LEVEL=info

# Rate Limiting
RATE_LIMIT_WINDOW=900000
RATE_LIMIT_MAX_REQUESTS=100
```

## Environment Validation

The application includes environment validation to ensure all required variables are set before startup.

### Setup Instructions

1. **Copy the environment variables** above into respective `.env` files
2. **Replace placeholder values** with your actual credentials
3. **Restart the development servers** after making changes
4. **Verify setup** by checking the console for validation messages

### Getting Credentials

#### Supabase
1. Create a project at [supabase.com](https://supabase.com)
2. Go to Project Settings > API
3. Copy the Project URL and anon/service_role keys

#### Stripe
1. Create an account at [stripe.com](https://stripe.com)
2. Go to Developers > API keys
3. Copy the publishable and secret keys (use test keys for development)

#### OAuth Providers
- **Google**: [Google Cloud Console](https://console.cloud.google.com)
- **Facebook**: [Facebook Developers](https://developers.facebook.com)

#### Analytics
- **Google Analytics**: [Google Analytics](https://analytics.google.com)
- **Mixpanel**: [Mixpanel](https://mixpanel.com)

## Security Notes

- Never commit `.env` files to version control
- Use different credentials for development, staging, and production
- Rotate secrets regularly
- Use environment-specific service accounts where possible 