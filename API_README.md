# Bucket & MediaID Backend API

## Phase 1 Implementation Complete ✅

This document outlines the newly implemented backend API structure for the Bucket & MediaID platform.

## Architecture Overview

### File Structure
```
Buckets_SB/
├── api/
│   └── router.ts              # Main API router
├── Routes/
│   ├── auth.ts               # Authentication endpoints
│   ├── subscriptions.ts      # Subscription management
│   └── mediaid.ts           # MediaID preferences & analytics
├── middleware/
│   ├── cors.ts              # CORS handling
│   ├── validation.ts        # Request validation
│   └── error-handling.ts    # Error handling & rate limiting
├── utils/
│   └── responses.ts         # Standardized API responses
└── database/
    ├── migrations/
    │   ├── 001_initial_schema.sql
    │   └── 002_rls_policies.sql
    └── ...
```

## API Endpoints

### Authentication Routes (`/auth`)

#### POST `/auth/signup`
Create a new user account with role-specific setup.

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "SecurePassword123",
  "userData": {
    "display_name": "John Doe",
    "role": "fan" | "artist" | "brand" | "developer"
  }
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "user": { ... },
    "message": "Account created successfully. Please check your email for verification."
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### POST `/auth/login`
Authenticate user credentials.

#### POST `/auth/refresh`
Refresh JWT token.

#### POST `/auth/logout`
Sign out user session.

### Subscription Routes (`/subscriptions`)

#### POST `/subscriptions/create-checkout`
Create Stripe Checkout session for artist subscription.

**Request Body:**
```json
{
  "artistId": "uuid",
  "tier": "basic",
  "priceId": "price_stripe_id",
  "successUrl": "https://app.com/success",
  "cancelUrl": "https://app.com/cancel"
}
```

#### GET `/subscriptions/{userId}`
Get user's active subscriptions.

#### PATCH `/subscriptions/{id}/cancel`
Cancel subscription at period end.

#### POST `/subscriptions/webhooks/stripe`
Handle Stripe webhook events.

### MediaID Routes (`/mediaid`)

#### GET `/mediaid/preferences`
Get user's MediaID preferences and privacy settings.

#### PUT `/mediaid/preferences`
Update MediaID interests and privacy settings.

**Request Body:**
```json
{
  "interests": ["music", "art", "fashion"],
  "privacy_settings": {
    "data_sharing": true,
    "location_access": false,
    "audio_capture": false,
    "anonymous_logging": true,
    "marketing_communications": false
  }
}
```

#### GET `/mediaid/analytics`
Get user's engagement analytics.

#### POST `/mediaid/events`
Log user interaction events.

#### DELETE `/mediaid/data`
Delete all user MediaID data (GDPR compliance).

## Middleware Features

### CORS Handling
- Configurable allowed origins
- Automatic preflight handling
- Security headers

### Request Validation
- Type checking for request bodies
- Required field validation
- Email and password validation
- File upload validation

### Error Handling
- Standardized error responses
- Custom error types (ValidationError, AuthenticationError, etc.)
- Error logging and debugging
- Rate limiting protection

### Rate Limiting
- IP-based rate limiting
- Configurable limits per endpoint
- Automatic cleanup of expired entries

## Response Format

All API responses follow a consistent format:

### Success Response
```json
{
  "success": true,
  "data": { ... },
  "message": "Optional success message",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

### Error Response
```json
{
  "success": false,
  "error": "Error message",
  "details": { ... },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

### Paginated Response
```json
{
  "success": true,
  "data": [ ... ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total": 100,
    "totalPages": 5,
    "hasNext": true,
    "hasPrev": false
  },
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## Security Features

### Authentication
- JWT-based authentication
- Secure token refresh
- Session management

### Authorization
- Role-based access control (RBAC)
- Row-level security (RLS)
- Resource ownership validation

### Data Protection
- Input validation and sanitization
- SQL injection prevention
- XSS protection through response headers

### Privacy Compliance
- GDPR-compliant data deletion
- Granular privacy controls
- Anonymous logging options

## Environment Variables

See `ENVIRONMENT_SETUP.md` for complete environment configuration.

Key variables:
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key for admin operations
- `STRIPE_SECRET_KEY` - Stripe secret key for payments
- `CORS_ORIGINS` - Allowed origins for CORS

## Usage Examples

### Frontend Integration

```typescript
// Using the new API structure
import { env } from '../lib/env-validation'

const api = {
  baseUrl: env.apiUrl,
  
  async post(endpoint: string, data: any, token?: string) {
    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token && { 'Authorization': `Bearer ${token}` })
      },
      body: JSON.stringify(data)
    })
    
    return response.json()
  }
}

// Example: Create subscription
const subscription = await api.post('/subscriptions/create-checkout', {
  artistId: 'artist-uuid',
  tier: 'premium',
  priceId: 'price_1234',
  successUrl: window.location.origin + '/success',
  cancelUrl: window.location.origin + '/cancel'
}, userToken)
```

## Next Steps (Phase 2)

1. **Content Management APIs**
   - File upload handling
   - Content scheduling
   - Milestone-based unlocking

2. **Brand Campaign APIs**
   - Campaign creation and management
   - Targeting and analytics
   - Performance tracking

3. **Advanced Features**
   - Real-time notifications
   - Advanced analytics
   - Third-party integrations

## Testing

Run the API server:
```bash
cd Buckets_SB
deno run --allow-net --allow-env api/router.ts
```

The API will be available at `http://localhost:8000`

## Health Check

GET `/` returns:
```json
{
  "success": true,
  "data": {
    "message": "Bucket & MediaID API",
    "version": "1.0.0",
    "status": "healthy"
  }
}
``` 