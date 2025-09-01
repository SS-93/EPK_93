# Tech Stack Document

This document explains the technology choices for our Event Management & Voting Platform in plain language. It covers how each piece works together to create a smooth experience for hosts, fans, artists, brands, admins, and developers.

## 1. Frontend Technologies

We build the part of the app you see and click with these tools:

- React (with TypeScript)
  • A popular library for building web interfaces. TypeScript adds helpful checks to avoid bugs early.  
  • Lets us create reusable components (buttons, forms, vote meters) that feel consistent.
- Styling with Styled-Components
  • A way to write component-specific styles in JavaScript files.  
  • Keeps design and code together, so changing a color or font is easy and stays in sync with branding.
- Internationalization (i18next)
  • Supports English and Spanish out of the box.  
  • Fans and hosts see labels, buttons, and messages in their language without reloading pages.
- Socket.IO (future real-time updates)
  • Enables live vote counts and leaderboards without refreshing the page.  
  • For MVP we may poll at short intervals, then switch on websockets for instant feedback.
- Responsive & Mobile-First Design
  • CSS media queries ensure the interface works on any device—desktop, tablet, or phone.  
  • Fans join via SMS and click on mobile screens, so every view is optimized for touch.

These choices make the interface fast, interactive, and easy to update when we change colors or add a new language.

## 2. Backend Technologies

The invisible engine behind the scenes uses:

- Node.js with Express (or NestJS)
  • A server framework written in JavaScript.  
  • Handles requests: creating events, casting votes, sending SMS, and more.
- JSON Web Tokens (JWT)
  • Secure tokens grant temporary voting rights and verify identities without storing passwords.  
  • Keeps each vote tied to a valid session or SMS token.
- PostgreSQL Database
  • A reliable, structured database to store events, artists, attendees, votes, messages, and audit logs.  
  • Supports complex queries (leaderboards, segment filters) and scales as data grows.
- RESTful API Endpoints
  • Clear URLs and HTTP methods (POST, GET) let the frontend and third parties create events, invite artists, register attendees, and record votes.  
  • Well-documented so outside developers can integrate easily.

Together, these components manage data securely, enforce voting rules, and power the CRM-lite features.

## 3. Infrastructure and Deployment

To host, deploy, and maintain the platform reliably, we use:

- AWS Cloud Services
  • EC2 (servers) to run the backend code.  
  • RDS (managed PostgreSQL) for our database.  
  • S3 for storing media (artist photos, cover images).  
  • CloudFront as a CDN to deliver static files (JavaScript, CSS) quickly around the world.
- GitHub & GitHub Actions
  • We keep all code in GitHub and use GitHub Actions for automated testing and deployment.  
  • Every time we merge code, tests run and, on success, new versions roll out to a staging or production environment.
- Version Control with Git
  • Tracks every change.  
  • Enables code reviews and safe rollbacks if something goes wrong.
- Monitoring and Alerts
  • AWS CloudWatch logs server metrics and sets alarms (CPU, memory, error rates).  
  • Sentry captures runtime errors so we can fix issues before they affect many users.
- Scalability & Auto-Scaling
  • We configure AWS to add more server instances when vote traffic spikes (for example, last-minute voting surges).  
  • Keeps performance smooth even if hundreds of people vote at once.

These infrastructure decisions make deployments predictable, reliable, and able to grow with demand.

## 4. Third-Party Integrations

Rather than building everything from scratch, we connect with proven services:

- Twilio (SMS)
  • Sends and receives text messages on a short code.  
  • Manages opt-in compliance, delivers join links and reminders in seconds.
- SendGrid or Mailgun (Email)
  • Handles welcome emails, result announcements, and follow-up campaigns.  
  • Tracks delivery, opens, and click rates for analytics.
- Google Analytics & Mixpanel
  • Capture user behavior on event pages and registration flows.  
  • Provide dashboards for hosts to see funnel drop-off, vote velocity, and conversion rates.
- Cursor IDE (AI-powered coding assistant)
  • Helps developers write code faster and with fewer errors.  
  • Suggests common patterns for API endpoints, database queries, and tests.
- Future Payment Gateway (e.g., Stripe)
  • Ready to integrate for platform billing, per-event fees, or subscriptions.  
  • Not in MVP but planned for later.

These integrations let us focus on the core event and voting experience while leveraging mature platforms for messaging and analytics.

## 5. Security and Performance Considerations

We’ve baked in measures to protect data and keep the app snappy:

- Encryption & Data Protection
  • TLS (HTTPS) everywhere ensures data in transit is secure.  
  • Database encryption at rest for PII (phone numbers, emails) with consent flags tracked.
- Role-Based Access Control
  • Fans, Artists, Brands, Admins, and Developers each have a clear permissions matrix.  
  • Prevents unauthorized access to sensitive actions (event creation, raw PII exports).
- Anti-Abuse Controls
  • One one-time vote token per attendee per round.  
  • Rate limiting by IP and device fingerprint to prevent vote stuffing.  
  • Optional SMS code verification for stricter security.
- Performance Tuning
  • API responses optimized to under 150 ms for common requests.  
  • Database indexes on frequently queried columns (event_id, round, token_id).  
  • Caching static resources via CloudFront and server-side caching for leaderboard data.
- Real-Time vs. Polling
  • Socket.IO planned for instant updates.  
  • In MVP, short-interval polling (e.g., every 5 seconds) ensures near-real-time vote display without complex scaling concerns.

These steps keep user data safe and the voting experience fast and reliable.

## 6. Conclusion and Overall Tech Stack Summary

Our chosen stack balances speed of development, user experience, and future growth:

- Frontend: React + TypeScript + Styled-Components + i18next for a flexible, bilingual UI.
- Backend: Node.js + Express/NestJS + JWT + PostgreSQL for secure, structured data handling.
- Infrastructure: AWS (EC2, RDS, S3, CloudFront) + GitHub Actions + Sentry/CloudWatch for reliable deployment and monitoring.
- Integrations: Twilio for SMS, SendGrid/Mailgun for email, Google Analytics & Mixpanel for insights.
- Security & Performance: TLS everywhere, role-based permissions, anti-abuse tokens, and caching.

This combination delivers a low-friction, role-aware platform that scales from a single event of 50–100 attendees to larger activations, while remaining easy to maintain, secure, and ready for future enhancements like multi-round voting and payment processing.