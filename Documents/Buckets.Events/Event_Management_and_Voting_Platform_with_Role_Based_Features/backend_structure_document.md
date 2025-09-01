# Backend Structure Document

## 1. Backend Architecture

We’re using a modular, service-oriented Node.js backend built on Express. Here’s how it all hangs together:

- **Structure and Patterns**
  - Model–View–Controller (MVC) style organization: models for data, controllers for business logic, routes for HTTP handling.
  - Repository pattern for data access, keeping SQL logic separate from services.
  - Services layer encapsulates core features (events, voting, messaging).
  - Middleware for concerns like authentication, error handling, and logging.

- **Frameworks and Libraries**
  - Express.js for HTTP routing.
  - Sequelize or TypeORM as an ORM for PostgreSQL.
  - JSON Web Tokens (JWT) for stateless auth.
  - Twilio SDK for SMS, SendGrid SDK for email.
  - Socket.IO for real-time vote updates.

- **Scalability, Maintainability, Performance**
  - Stateless services behind a load balancer let us spin up more instances on demand.
  - Layered codebase and clear separation of concerns simplify updates and new features.
  - Caching hot data (leaderboards, event config) in Redis reduces database load.
  - Horizontal scaling of Node.js processes via Docker and AWS ECS/EKS ensures we can handle spikes in traffic.

---

## 2. Database Management

- **Technology**
  - PostgreSQL (relational SQL database).

- **Data Organization**
  - Events, artists, attendees, votes, users, and messaging tables.
  - A JSON column (`vote_config`) in the events table to flexibly store voting rules.
  - Foreign keys enforce relationships (e.g., each vote links to an attendee and an event).

- **Access and Practices**
  - Use an ORM (Sequelize/TypeORM) to prevent SQL injection and simplify migrations.
  - Regular backups via AWS RDS snapshots.
  - Indexes on foreign keys and commonly queried fields (event date, status, phone number).

---

## 3. Database Schema

### Human-Readable Overview

- **users**: All platform users (fans, artists, admins, developers).
  - id, email, passwordHash, role, languagePref, createdAt

- **events**: Contains event settings and state.
  - id, title, startDate, endDate, venue, accessType, voteConfig, status, createdBy, timestamps

- **artists**: Profiles for each artist.
  - id, name, bio, socialLinks (JSON), claimedByUserId, status

- **event_artists**: Links artists to events.
  - eventId, artistId, inviteStatus, joinedAt

- **attendees**: Fans who join events via SMS.
  - id, eventId, phoneNumber, email, joinedAt, optedOut

- **votes**: Records each vote cast.
  - id, attendeeId, eventId, artistId, round, token, createdAt

- **messages**: SMS/email sent (JOIN, CONFIRM, NUDGE, RESULTS, RECAP).
  - id, attendeeId, eventId, channel, messageType, status, sentAt

### SQL Schema (PostgreSQL)

```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(20) NOT NULL,
  language_pref VARCHAR(5) DEFAULT 'en',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE events (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  start_date TIMESTAMP NOT NULL,
  end_date TIMESTAMP NOT NULL,
  venue TEXT,
  access_type VARCHAR(10) CHECK (access_type IN ('public','private','hybrid')) NOT NULL,
  vote_config JSONB NOT NULL,
  status VARCHAR(20) CHECK (status IN ('draft','published','live','closed','archived')) NOT NULL,
  created_by INTEGER REFERENCES users(id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE artists (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  bio TEXT,
  social_links JSONB,
  claimed_by_user_id INTEGER REFERENCES users(id),
  status VARCHAR(20) CHECK (status IN ('invited','claimed','approved','withdrawn')) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE event_artists (
  event_id INTEGER REFERENCES events(id),
  artist_id INTEGER REFERENCES artists(id),
  invite_status VARCHAR(20) CHECK (invite_status IN ('pending','accepted','declined')),
  joined_at TIMESTAMP,
  PRIMARY KEY (event_id, artist_id)
);

CREATE TABLE attendees (
  id SERIAL PRIMARY KEY,
  event_id INTEGER REFERENCES events(id),
  phone_number VARCHAR(20) NOT NULL,
  email VARCHAR(255),
  joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  opted_out BOOLEAN DEFAULT FALSE
);

CREATE TABLE votes (
  id SERIAL PRIMARY KEY,
  attendee_id INTEGER REFERENCES attendees(id),
  event_id INTEGER REFERENCES events(id),
  artist_id INTEGER REFERENCES artists(id),
  round INTEGER NOT NULL,
  token VARCHAR(100) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE messages (
  id SERIAL PRIMARY KEY,
  attendee_id INTEGER REFERENCES attendees(id),
  event_id INTEGER REFERENCES events(id),
  channel VARCHAR(10) CHECK (channel IN ('sms','email')) NOT NULL,
  message_type VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL,
  sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## 4. API Design and Endpoints

We use a RESTful approach with JSON payloads. All endpoints require a JWT token in the `Authorization` header (except public event info).

- **User & Auth**
  - POST /auth/signup – Register a new user (returns JWT).
  - POST /auth/login – Login and receive JWT.
  - GET /auth/profile – Get current user info.

- **Events**
  - POST /events – Create a new event.
  - GET /events – List events (with filters by status, date).
  - GET /events/:id – Get event details (public view or admin view).
  - PUT /events/:id – Update event settings.
  - POST /events/:id/publish – Transition event to Published.

- **Artists & Invites**
  - POST /events/:id/artists – Invite an artist.
  - GET /events/:id/artists – List invited artists.
  - POST /artists/:id/claim – Artist claims profile.

- **Attendees & Voting**
  - POST /sms/join – Twilio webhook: handle SMS JOIN keywords.
  - POST /attendees/:id/confirm – Confirm phone via link or code.
  - POST /events/:id/vote – Cast a vote (round and token in body).
  - GET /events/:id/leaderboard – Get current standings.

- **Messaging**
  - POST /events/:id/messages – Send broadcast SMS/email.
  - GET /events/:id/messages – View message history.

- **Admin & Reporting**
  - GET /events/:id/report – Download CSV/XLS of attendees and votes.
  - GET /analytics/events/:id – Real-time stats via JSON or SSE.

---

## 5. Hosting Solutions

We’re fully on AWS for reliability and scale:

- **Compute**
  - Docker containers on ECS Fargate (or EKS) for the Node.js API.
  - Autoscaling groups adjust the number of tasks based on CPU/memory.

- **Database**
  - Amazon RDS for PostgreSQL in a Multi-AZ setup for high availability.

- **Storage & CDN**
  - S3 for static assets and event recap pages.
  - Amazon CloudFront CDN distributes assets globally.

- **Benefits**
  - Managed services reduce ops overhead.
  - Pay-as-you-go keeps costs aligned with usage.
  - Built-in redundancy and scaling handles traffic spikes.

---

## 6. Infrastructure Components

- **Load Balancer**
  - AWS Application Load Balancer (ALB) routes HTTP(s) traffic to API tasks.

- **Caching**
  - Amazon ElastiCache (Redis) for:
    - Leaderboard cache for fast, live vote updates.
    - Session/token blacklist for JWT invalidation.

- **Queueing & Background Jobs**
  - Amazon SQS for message queueing (e.g., SMS retries, email batches).
  - AWS Lambda or ECS tasks pull jobs to send SMS/email.

- **Real-Time Updates**
  - Socket.IO running alongside the API, backed by Redis pub/sub for cross-instance messaging.

---

## 7. Security Measures

- **Authentication & Authorization**
  - JWT with short expiry and refresh tokens.
  - Role-based access control (Fan, Artist, Brand, Admin, Developer).

- **Encryption**
  - TLS everywhere (API and web traffic).
  - Data-at-rest encryption for RDS and S3.

- **Data Protection**
  - Input validation and sanitization to prevent injection attacks.
  - ORM for parameterized queries.
  - Rate limiting at the ALB or API Gateway to prevent abuse.

- **Compliance & Privacy**
  - SMS opt-in/opt-out tracking in attendees table.
  - Privacy mode aggregates sponsor data to remove PII.

---

## 8. Monitoring and Maintenance

- **Logging & Metrics**
  - AWS CloudWatch for infrastructure logs, metrics, and alarms.
  - Application logs forwarded to CloudWatch Logs or an ELK stack.
  - Custom metrics (e.g., vote rate, SMS delivery rate) sent to CloudWatch.

- **Error Tracking**
  - Sentry (or AWS X-Ray) for exception monitoring and tracing.

- **Uptime & Health Checks**
  - ALB health checks on API endpoints (`/health`).
  - Automated failover in RDS Multi-AZ.

- **CI/CD**
  - GitHub Actions or AWS CodePipeline:
    - Lint, test, build Docker image.
    - Deploy to ECS/EKS.
  - Database migrations applied automatically during deploy.

- **Maintenance**
  - Scheduled maintenance windows via AWS RDS.
  - Regular dependency updates and security scans.

---

## 9. Conclusion and Overall Backend Summary

Our backend is a robust, AWS-hosted Node.js service with a PostgreSQL database that handles event creation, SMS-based joining, live voting, and CRM-style messaging. We use clear separation of concerns (MVC + services), industry-standard security (TLS, JWT, RBAC), and managed AWS components (ECS, RDS, ElastiCache) to ensure reliability, scalability, and cost efficiency. Real-time updates via Socket.IO and caching in Redis deliver fast leaderboards, while Twilio and SendGrid handle SMS/email journeys. Monitoring and CI/CD pipelines keep us healthy and agile.

This structure supports our goal of a low-friction, role-aware event and voting platform that can grow with our users and deliver a seamless live experience.