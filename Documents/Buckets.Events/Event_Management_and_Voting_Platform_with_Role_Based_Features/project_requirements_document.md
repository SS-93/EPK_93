# Project Requirements Document

## 1. Project Overview

This Event Management & Voting Platform lets hosts create and run live voting events that anyone can join simply by texting a keyword—no app installation required. Hosts (Admins) configure event details, voting rules and SMS workflows in a guided setup wizard. Fans join via SMS, complete a lightweight registration, and cast votes on their favorite artists. Artists claim and lock their profiles for the event, then track votes and fan engagement in a backstage dashboard. Brands can sponsor events and receive anonymized engagement reports. Developers can integrate via REST APIs and webhooks or embed voting widgets on partner sites.

We’re building this platform to offer a low-friction, role-aware solution that turns interactions into actionable data (lightweight CRM). By capturing every join, vote and follow-up, hosts drive deeper engagement and measure success through real-time analytics. Key objectives for MVP success are:

1.  Smooth event creation and SMS-driven fan onboarding
2.  Secure, configurable single-round voting with live leaderboard
3.  Basic CRM messaging and post-event recap pages
4.  Clear dashboards for all user roles

## 2. In-Scope vs. Out-of-Scope

### In-Scope (MVP)

*   Event creation wizard (title, dates, venue, public/private, cover art, sponsor tags)
*   Single-round voting with configurable vote limit and tiebreaker
*   SMS keyword setup (Twilio-style) and reply templates
*   SMS-driven join flow with lightweight registration (phone + optional name/email + consent)
*   Live leaderboard (end-of-round reveal)
*   Artist claim form and profile lock
*   Basic backstage dashboards (votes count, top geos)
*   CRM-lite messaging console (segment filters, SMS/email broadcast)
*   Post-event recap pages for fans, artists and hosts
*   Exports: attendees CSV, vote aggregates
*   REST API endpoints for events, invites, joins, votes
*   Webhooks: vote.created, attendee.joined, artist.claimed

### Out-of-Scope (Later Phases)

*   Multi-round bracket voting
*   Real-time leaderboard updates via WebSocket
*   A/B testing for messaging templates
*   Brand sponsorship panel and detailed brand reports
*   Advanced anomaly-detection dashboard
*   Hybrid public/private toggles beyond basic private mode
*   Payment gateway or monetization flows
*   In-depth UGC (fan comments)
*   Full Buckets platform integrations (beyond invites)

## 3. User Flow

When an Admin (Host) logs in, they land on an **Event Setup Wizard**. Step-by-step they enter basics (title, date, venue, public/private), define voting rules (one round, 5 votes per attendee, tiebreaker), set SMS keyword and reply templates, and review SMS/consent language. Clicking “Publish” launches the event page, generates join/vote links, and activates the SMS workflow.

A Fan texts the keyword to the event number and receives a link to an inline registration page with their phone pre-filled. After consenting, they see the artist lineup and a badge showing “5 votes available.” They tap artist cards to cast votes (one per tap), get a toast confirmation, then view a recap screen with CTAs to follow artists or subscribe to reminders. Artists claim via a separate link, submit their profile, and access a private dashboard showing vote counts and simple analytics. Developers can subscribe to webhooks or pull data from REST endpoints and embed voting widgets in other sites.

## 4. Core Features

*   **Event Creation Wizard**\
    Hosts define event basics, visibility, cover art, sponsor tags, vote rules, SMS keyword, templates and compliance language.
*   **SMS-Driven Low-Friction Entry**\
    Keyword trigger → smart link → lightweight registration → instant lineup + vote badge.
*   **Configurable Voting Engine**\
    Single round, vote limit per attendee, tiebreaker rule, end-of-round leaderboard reveal, vote metadata (timestamp, source, token).
*   **Artist Onboarding & Lock**\
    Invite links → profile claim form → lock snapshot → backstage dashboard.
*   **CRM-Lite Messaging & Segmentation**\
    Segment by joined-only, partial voters, heavy voters, unsubscribed; send SMS/email campaigns with templates.
*   **Analytics & Reporting**\
    Dashboards for join funnel, vote velocity curve, round summary, conversion rates, messaging metrics; simple CSV exports.
*   **REST API & Webhooks**\
    Endpoints for event management, artist invites, attendee joins, votes; webhooks for real-time integration.
*   **Permission Matrix**\
    Role-based access: Fan, Artist, Brand (view/report), Admin (full control), Developer (API/webhooks).

## 5. Tech Stack & Tools

*   **Frontend**: React (TypeScript), Socket.IO (future real-time)
*   **Backend**: Node.js (Express or Nest.js), JWT for tokens
*   **Database**: PostgreSQL
*   **Hosting & Infra**: AWS (EC2, RDS, S3, CloudFront)
*   **SMS Provider**: Twilio-style (cost-effective short codes)
*   **Email Provider**: SendGrid or Mailgun
*   **Analytics**: Google Analytics, Mixpanel
*   **IDE & AI Assistant**: Cursor
*   **CI/CD**: GitHub Actions
*   **Monitoring**: AWS CloudWatch, Sentry

## 6. Non-Functional Requirements

*   **Performance**:\
    • Page load <200 ms\
    • SMS send latency <5 s\
    • API response <150 ms under 100 concurrent users
*   **Security & Compliance**:\
    • TLS everywhere\
    • Encryption at rest for PII\
    • GDPR/CCPA-style consent logging\
    • Role-based access controls
*   **Availability & Scalability**:\
    • 99.9% uptime SLA\
    • Auto-scaling for sudden vote bursts
*   **Usability**:\
    • Mobile-first design\
    • Bilingual support (English, Spanish)\
    • Accessible forms (WCAG AA)

## 7. Constraints & Assumptions

*   Initial scale: 1 event at a time, 50–100 concurrent attendees/votes.
*   English and Spanish languages only for MVP.
*   No social logins—phone+email registration only.
*   Sponsors receive aggregate-only data in privacy mode.
*   Must integrate cost-effective SMS/email providers.
*   Host configures single-round voting (no brackets yet).
*   WebSockets reserved for future; MVP uses polling or manual refresh.

## 8. Known Issues & Potential Pitfalls

*   **SMS Throughput Limits**\
    • Short code capacity may throttle messages → implement exponential back-off and retry queue.
*   **API Rate Limits**\
    • External analytics tools have quotas → batch events and fallback to local caching.
*   **Token Abuse**\
    • Duplicate devices or phone reuse → enforce one active vote token per round, optional SMS code re-verification.
*   **Late Artist Claims**\
    • Claims after lock cutoff → mark as “Late Entry” or queue for next event.
*   **Privacy-First Mode**\
    • Sponsors demand more granularity → clarify aggregate only vs. cohort insights at build time.
*   **Real-Time Leaderboard**\
    • WebSocket scaling complexity → MVP end-of-round refresh only; plan for Socket.IO in v1.1.

This PRD gives a clear blueprint for AI-driven development of the MVP. It defines project goals, scope boundaries, user journeys, core modules, technical choices, and key operational considerations—leaving no room for ambiguity.
