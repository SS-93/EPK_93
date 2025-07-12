# Authentication + MediaID API Specifications

## Base URL
- Development: `https://your-project.supabase.co/functions/v1`
- Production: `https://your-domain.com/api`

## Authentication Flow

### 1. User Signup
**POST** `/auth-signup`

**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "securePassword123",
  "userData": {
    "display_name": "John Doe", 
    "role": "fan" | "artist" | "brand"
  }
}
```

**Response (Success):**
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "user_metadata": { ... }
  },
  "message": "Account created successfully. Please check your email for verification."
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "Error message"
}
```

### 2. MediaID Setup (Post-Signup)
**POST** `/mediaid-setup`
**Headers:** `Authorization: Bearer <jwt_token>`

**Request Body:**
```json
{
  "interests": ["electronic", "indie-rock", "jazz"],
  "genre_preferences": ["ambient", "lo-fi"],
  "location_code": "NYC",
  "privacy_settings": {
    "data_sharing": true,
    "location_access": false,
    "audio_capture": false,
    "anonymous_logging": true,
    "marketing_communications": false
  },
  "content_flags": {
    "mood": "energetic",
    "discovery_preference": "new_artists"
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "MediaID setup completed successfully"
}
```

**Validation Rules:**
- `interests`: Array of 3-5 strings required
- `privacy_settings`: All boolean fields required
- `location_code`: Optional string
- `content_flags`: Optional object

## Database Tables Available for Frontend

### Available via Supabase Client (with RLS):

#### `profiles`
```typescript
interface Profile {
  id: string
  display_name: string | null
  avatar_url: string | null
  role: 'fan' | 'artist' | 'brand' | 'admin'
  email_verified: boolean
  onboarding_completed: boolean
  created_at: string
  updated_at: string
}
```

#### `media_ids`
```typescript
interface MediaID {
  id: string
  user_uuid: string
  interests: string[]
  genre_preferences: string[]
  content_flags: Record<string, any>
  location_code: string | null
  privacy_settings: {
    data_sharing: boolean
    location_access: boolean
    audio_capture: boolean
    anonymous_logging: boolean
    marketing_communications: boolean
  }
  created_at: string
  updated_at: string
}
```

#### `artists` (Public Read)
```typescript
interface Artist {
  id: string
  user_id: string
  artist_name: string
  bio: string | null
  banner_url: string | null
  social_links: Record<string, any>
  verification_status: string
  created_at: string
  updated_at: string
}
```

#### `subscriptions` (User's Own)
```typescript
interface Subscription {
  id: string
  fan_id: string
  artist_id: string
  tier: string
  price_cents: number
  status: 'active' | 'canceled' | 'paused' | 'expired'
  stripe_subscription_id: string | null
  current_period_start: string | null
  current_period_end: string | null
  cancel_at_period_end: boolean
  created_at: string
  updated_at: string
}
```

#### `content_items` (Unlocked for Subscribers)
```typescript
interface ContentItem {
  id: string
  artist_id: string
  title: string
  description: string | null
  content_type: 'audio' | 'video' | 'image' | 'document'
  file_path: string
  file_size_bytes: number | null
  duration_seconds: number | null
  unlock_date: string | null
  milestone_condition: Record<string, any> | null
  is_premium: boolean
  metadata: Record<string, any>
  created_at: string
  updated_at: string
}
```

### Protected Tables (API-only):
- `brands` - Brand data (restricted access)
- `campaigns` - Campaign data (role-based)
- `media_engagement_log` - Analytics (privacy-controlled)
- `transactions` - Payment data (secure functions only)

## Integration Examples

### Frontend Signup Flow
```typescript
// 1. Signup
const signupResponse = await fetch('/functions/v1/auth-signup', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    email: 'user@example.com',
    password: 'password123',
    userData: {
      display_name: 'John Doe',
      role: 'fan'
    }
  })
})

// 2. Login with Supabase (after email verification)
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'user@example.com',
  password: 'password123'
})

// 3. Setup MediaID
const mediaIdResponse = await fetch('/functions/v1/mediaid-setup', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${data.session.access_token}`
  },
  body: JSON.stringify({
    interests: ['electronic', 'jazz', 'ambient'],
    genre_preferences: ['lo-fi', 'experimental'],
    privacy_settings: {
      data_sharing: true,
      location_access: false,
      audio_capture: false,
      anonymous_logging: true,
      marketing_communications: false
    }
  })
})
```

### Supabase RLS Queries
```typescript
// Get user profile (own data only)
const { data: profile } = await supabase
  .from('profiles')
  .select('*')
  .eq('id', user.id)
  .single()

// Get user MediaID (own data only)
const { data: mediaId } = await supabase
  .from('media_ids')
  .select('*')
  .eq('user_uuid', user.id)
  .single()

// Browse artists (public)
const { data: artists } = await supabase
  .from('artists')
  .select('*')
  .order('created_at', { ascending: false })

// Get user subscriptions (own data only)
const { data: subscriptions } = await supabase
  .from('subscriptions')
  .select(`
    *,
    artists (
      id,
      artist_name,
      banner_url
    )
  `)
  .eq('fan_id', user.id)
  .eq('status', 'active')
```

## Error Handling

All endpoints return consistent error responses:

```json
{
  "success": false,
  "error": "Descriptive error message"
}
```

Common error codes:
- **400**: Bad Request (validation failed)
- **401**: Unauthorized (invalid/missing token)
- **403**: Forbidden (RLS policy denied)
- **404**: Not Found
- **500**: Internal Server Error

## Rate Limiting

- Auth endpoints: 5 requests per minute per IP
- MediaID setup: 1 request per minute per user
- General API: 100 requests per minute per user

## Security Notes

1. **RLS Enforcement**: All queries automatically filtered by user permissions
2. **JWT Validation**: All protected endpoints require valid Supabase JWT
3. **Privacy First**: MediaID data never exposed without explicit consent
4. **Anonymous Logging**: Engagement tracking respects user privacy settings
5. **Data Encryption**: All data encrypted in transit and at rest 