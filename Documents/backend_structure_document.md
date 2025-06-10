# Backend Structure Document

This document outlines the backend architecture, hosting setup, and infrastructure components for the Bucket & MediaID platform. It is written in clear, everyday language so that anyone—technical or non-technical—can understand how everything fits together.

---

## 1. Backend Architecture

**Overall Design**
- We’re using Supabase as our core backend-as-a-service. Supabase gives us:
  - Authentication (including social logins)
  - A managed PostgreSQL database
  - Storage for media files (audio, video, images)
  - Real-time data (via websockets)
- For any custom business logic that goes beyond Supabase’s built-in features, we use serverless functions (Edge Functions) written in TypeScript. These functions live alongside Supabase and scale automatically.

**Patterns and Frameworks**
- Repository Pattern: clean separation of data-access code from business logic
- MVC-style approach inside each function: 
  - Model (database queries)
  - Controller (business rules)
  - Service (external integrations, e.g. Stripe)
- Event-driven hooks: when a user subscribes or uploads content, we trigger background tasks (notifications, analytics updates).

**Scalability, Maintainability, Performance**
- Supabase scales the database and storage automatically—no servers to manage.
- Serverless functions scale out under load, so spikes in traffic (e.g., viral artist launches) are handled gracefully.
- We keep our code modular: each feature (subscriptions, content locker, MediaID) lives in its own set of functions and database schema. That makes updates and bug fixes easier.

---

## 2. Database Management

**Technology**
- SQL Database: PostgreSQL (managed by Supabase)
- No separate NoSQL store—PostgreSQL’s JSONB fields handle flexible data (like user preferences).
- File Storage: Supabase Storage buckets for audio, video, and image files.

**Data Structure & Practices**
- Tables for core entities: users, artists, fans, brands, subscriptions, content items, campaigns, transactions.
- JSONB columns for flexible, semi-structured data such as MediaID preferences and event logs.
- Regular automated backups (daily snapshots) and Point-In-Time Recovery still managed by Supabase.
- Migrations tracked in Git: each schema change is a versioned SQL file.

---

## 3. Database Schema

Below is a high-level view of our main tables. This is human-readable; beneath it is the actual SQL for PostgreSQL.

Artists
- id (UUID)
- user_id (UUID linking to users)
- profile details (name, bio, avatar_url)

Fans
- id (UUID)
- user_id (UUID linking to users)
- subscription settings

Brands
- id (UUID)
- name, contact info, billing details

Subscriptions
- id (UUID)
- fan_id, artist_id
- tier, price, start_date, status

Content_Items
- id (UUID)
- artist_id
- type (audio, video, image)
- file_path (Storage URL)
- unlock_date

Campaigns
- id (UUID)
- brand_id, artist_id
- targeting_criteria (JSONB)
- payout_model

Preferences
- user_id (UUID)
- interests (JSONB array of tags)
- privacy_settings (JSONB)

Media_Engagement_Log
- id (UUID)
- user_id, content_id
- timestamp, event_type

Transactions
- id (UUID)
- user_id, amount, currency, type (subscription, payout)
- status, timestamp

---

**PostgreSQL Schema (example)**
```sql
CREATE TABLE artists (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  name TEXT,
  bio TEXT,
  avatar_url TEXT
);

CREATE TABLE fans (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  subscription_tier TEXT,
  subscription_status TEXT
);

CREATE TABLE subscriptions (
  id UUID PRIMARY KEY,
  fan_id UUID REFERENCES fans(id),
  artist_id UUID REFERENCES artists(id),
  price_cents INT,
  tier TEXT,
  start_date TIMESTAMP,
  status TEXT
);

CREATE TABLE content_items (
  id UUID PRIMARY KEY,
  artist_id UUID REFERENCES artists(id),
  media_type TEXT,
  file_path TEXT,
  unlock_date TIMESTAMP
);

CREATE TABLE preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  interests JSONB,
  privacy_settings JSONB
);

CREATE TABLE media_engagement_log (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  content_id UUID REFERENCES content_items(id),
  event_type TEXT,
  timestamp TIMESTAMP
);

CREATE TABLE transactions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  amount_cents INT,
  currency TEXT,
  transaction_type TEXT,
  status TEXT,
  created_at TIMESTAMP
);
```

---

## 4. API Design and Endpoints

We follow a RESTful approach, served either directly by Supabase auto-generated endpoints or via our custom Edge Functions.

**Authentication**
- `POST /auth/signup` — sign up with email/password or social logins
- `POST /auth/login` — return JWT
- `POST /auth/refresh` — refresh expired tokens

**User & Profile**
- `GET /users/me` — fetch current user profile
- `PUT /users/me` — update profile fields, media preferences

**Artist Locker**
- `POST /artists/:id/content` — upload a new content item
- `GET /artists/:id/content?status=unlocked` — list unlocked items for a fan
- `PATCH /content/:id` — update unlock date or metadata

**Subscriptions & Payments**
- `POST /subscriptions` — fan subscribes to an artist (creates Stripe Checkout session)
- `GET /subscriptions/:fanId` — view current subscriptions
- `POST /webhooks/stripe` — handle Stripe events (payment succeeded, invoice created)

**Brand Campaigns**
- `POST /campaigns` — brand creates a new campaign
- `GET /campaigns/:brandId` — list a brand’s campaigns
- `GET /campaigns/:id/analytics` — impressions, engagements, conversions

**MediaID Preferences**
- `GET /mediaid/preferences` — fetch user interests and privacy settings
- `PUT /mediaid/preferences` — update interests or sharing preferences

**Analytics & Logs**
- `GET /analytics/artist/:id` — revenue and engagement metrics
- `GET /analytics/brand/:id` — campaign performance metrics

---

## 5. Hosting Solutions

**Supabase Cloud**
- Our primary backend services (PostgreSQL, Auth, Storage, Edge Functions) are hosted on Supabase’s managed infrastructure.
- Benefits:
  - Reliability: automated failover and backups
  - Scalability: instant vertical and horizontal scaling
  - Cost-effectiveness: pay for what we use

**CDN for Media**
- Supabase Storage has a built-in CDN for fast delivery of images, audio, and video worldwide.

---

## 6. Infrastructure Components

**Load Balancing**
- Supabase’s front door automatically distributes traffic across multiple compute nodes.

**Caching**
- We use in-memory caching (Redis) for hot reads—popular artist lockers, trending campaigns.
- API responses are cached at the CDN layer where appropriate.

**Content Delivery Network (CDN)**
- Supabase Storage + Cloudflare under the hood delivers media files globally with low latency.

**Background Tasks & Queues**
- For longer-running jobs (email notifications, batch analytics), we dispatch tasks via a simple queue service (e.g., Supabase’s Realtime or an external queue like RabbitMQ).

---

## 7. Security Measures

**Authentication & Authorization**
- JWT-based authentication through Supabase Auth.
- OAuth2 support for social logins (Google, Facebook).

**Role-Based Access Control (RBAC)**
- Supabase roles: `anon`, `user`, `artist`, `brand`, `admin`.
- Only artists can upload content; only fans on an active subscription can view locked content.

**Row-Level Security (RLS)**
- Enforced in PostgreSQL so each query automatically filters out unauthorized rows (e.g., fans only see their own subscriptions).

**Data Encryption**
- All data in transit is protected via TLS.
- At-rest encryption provided by Supabase.

**PCI Compliance**
- Payments go through Stripe Checkout—no credit-card data touches our servers.

**Privacy Controls**
- Users manage granular sharing settings in MediaID.
- We never expose raw personal data to brands—only aggregated or permissioned segments.

---

## 8. Monitoring and Maintenance

**Performance Monitoring**
- Supabase dashboard for database and function latency metrics.
- External APM (e.g., Datadog) for end-to-end tracing of our Edge Functions.

**Error Tracking**
- Sentry for capturing runtime errors in our serverless functions.

**Logs & Alerts**
- Centralized logs (via Logflare or an ELK stack) for audit trails and debugging.
- Alerts on high error rates or slow queries.

**Maintenance Strategy**
- Automated schema migrations via CI/CD when merging to main branch.
- Nightly backups and weekly restore drills.
- Quarterly security review and dependency updates.

---

## 9. Conclusion and Overall Backend Summary

The Bucket & MediaID backend is built around Supabase’s managed services, offering fast development, automatic scaling, and robust security. We use PostgreSQL for structured and flexible data storage, Stripe for safe payments, and serverless functions for custom logic. A combination of RBAC, RLS, and user-controlled privacy settings keeps data secure and compliant. Caching, CDN distribution, and isolated micro-services ensure we deliver content quickly, even under heavy load. Together, these pieces form a maintainable, high-performance foundation that supports artists, fans, and brands alike—while giving users full control over their data and preferences.