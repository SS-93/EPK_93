# Tech Stack Document for Bucket & MediaID

This document explains the technology choices behind Bucket & MediaID in plain language. Each section shows how the selected tools work together to deliver a smooth, secure, and scalable experience for artists, fans, and brand marketers.

## Frontend Technologies

We chose technologies that make the user interface fast, responsive, and visually appealing:

- **React**
  - A popular JavaScript library for building interactive user interfaces.
  - Lets us break the UI into reusable components (e.g., the Locker view, subscription cards, dashboards).
  - Quick updates to the screen when data changes (real-time engagement metrics, new content unlocks).

- **Tailwind CSS**
  - A utility-first styling framework: we use small, descriptive classes (e.g., `bg-black`, `text-gray-200`, `p-4`).
  - Speeds up design consistency and makes it easy to tweak colors, spacing, and typography.
  - Supports our minimal black-and-white aesthetic with accents in light gray and tan.

- **Framer Motion**
  - A library for smooth, light animations (e.g., Locker opening, content fade-ins).
  - Enhances user experience without overwhelming—subtle motion guides attention to new daily content or milestone releases.

- **Responsive Design**
  - The layout adapts to different screen sizes (desktop, tablet).
  - Ensures fans and artists can access core features from any device without dedicated mobile apps in MVP.

## Backend Technologies

The backend powers data storage, authentication, real-time updates, and payment processing:

- **Supabase**
  - An all-in-one backend platform built on PostgreSQL.
  - **Authentication & Authorization**: manages email/password and social logins (Google, Facebook).
  - **Storage**: securely stores audio, video, and image files for the Artist Locker.
  - **Real-time Database**: pushes live updates for dashboards (revenue graphs, engagement rates).
  - **Edge Functions**: run server-side tasks, such as scheduling daily content unlocks or processing webhooks.

- **PostgreSQL**
  - The core database for user profiles, MediaID preference graphs, and the media engagement ledger.
  - Supports **Row-Level Security (RLS)** to ensure each user or role sees only the data they’re allowed to access.

- **Stripe Checkout**
  - Handles all subscription and brand campaign payments.
  - Supports multiple billing models: flat fee, pay-per-engagement, pay-per-conversion.
  - Integrates with Supabase via secure server-side calls.

- **OAuth2 Token Management & Secure SDK**
  - Powers the MediaID developer API for third-party integrations.
  - Ensures consent-based access to anonymized preference data and event logs.

## Infrastructure and Deployment

These choices ensure reliable hosting, smooth deployments, and continuous integration:

- **Version Control**: GitHub
  - All code (frontend, backend functions, infrastructure configs) lives in Git repositories.
  - Pull requests and code reviews maintain quality and consistency.

- **CI/CD Pipeline**: GitHub Actions
  - Automatically runs tests and linters on every commit.
  - Deploys the frontend to Vercel and backend functions to Supabase on merge to `main`.

- **Hosting**:
  - **Vercel** for the React application (global CDN, instant cache invalidation).
  - **Supabase** managed hosting for Postgres, Auth, Storage, and Edge Functions.

- **Scalability & Caching**:
  - Supabase read replicas and edge caching for high-traffic dashboards.
  - Built-in CDN for media assets (audio, video, images).

## Third-Party Integrations

Additional services extend the platform’s capabilities:

- **Social Logins** (Google, Facebook)
  - Streamline signup and login flows.
  - Reduce friction for fans, artists, and brands.

- **Shopify** (Phase 2)
  - Enables artists to sell merchandise alongside digital content.

- **Spotify** (Future Integration)
  - Embeds music previews or link-outs for broader discovery.

- **Analytics Tools**
  - **Google Analytics**: tracks page views, user demographics, traffic sources.
  - **Mixpanel**: measures user actions (locker opens, subscription clicks, campaign engagements) with event-based reports.

## Security and Performance Considerations

We’ve built multiple layers of protection and optimization:

- **Authentication & Access Control**
  - Supabase Auth for secure login flows, including email verification.
  - Role-Based Access Control (RBAC) to differentiate Fans, Artists, and Brand Marketers.
  - Row-Level Security (RLS) ensures users only access their own data.

- **Data Privacy & Compliance**
  - GDPR/CCPA-aligned consent flows for data sharing.
  - Granular privacy settings in the MediaID dashboard: toggles for location, audio, event data, anonymous logging.
  - Transparent Media Engagement Ledger: users can view, manage, or clear recorded interactions.

- **API Security**
  - OAuth2 with short-lived tokens for third-party developer access.
  - Scoped permissions so partners see only aggregated or anonymized data.

- **Performance**
  - Page loads under 2 seconds; API calls under 200 ms.
  - Real-time dashboard updates under 1 second latency.
  - CDN caching for static assets and media files.

## Conclusion and Overall Tech Stack Summary

Bucket & MediaID bring together a modern, privacy-first technology stack that aligns with our goals:

- **Fast, Intuitive UI** with React, Tailwind CSS, and Framer Motion.
- **Robust Backend** powered by Supabase (PostgreSQL, Auth, Storage, Realtime, Edge Functions).
- **Flexible Payments** via Stripe Checkout, covering subscriptions and campaign billing.
- **Secure Identity & Consent** through OAuth2, RBAC, RLS, and a transparent MediaID ledger.
- **Scalable Infrastructure** on Vercel and Supabase with CI/CD pipelines.
- **Rich Integrations** for social logins, e-commerce, streaming, and analytics.

This combination ensures a seamless experience—fans enjoy daily discoveries, artists build sustainable revenue, and brands reach engaged audiences—all while users remain in control of their data.
