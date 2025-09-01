# Implementation plan

## Phase 1: Environment Setup

1. **Prevalidation**: In the project root, run `test -f package.json || echo "No package.json found"` to check if this is already a Node.js project. (Project Summary)
2. **Initialize Git**: If no Git repo exists, run `git init` in `/` to initialize version control. (Project Summary)
3. **Install Node.js**: Ensure you have Node.js v20.2.1 installed. If not, use `nvm install 20.2.1 && nvm use 20.2.1`. (Project Summary: Tech Stack)
4. **Validation**: Run `node -v` to confirm output is `v20.2.1`. (Project Summary: Tech Stack)
5. **Install AWS CLI v2**: Follow AWS docs to install AWS CLI v2. (Project Summary: Hosting & Infrastructure)
6. **Install Twilio CLI**: Run `npm install -g twilio-cli@4.17.1`. (Project Summary: SMS Provider)
7. **Install SendGrid CLI**: Run `npm install -g @sendgrid/cli@1.0.0`. (Project Summary: Email Provider)
8. **Create Root Folders**: Run:
   - `mkdir frontend`
   - `mkdir backend`
   in `/` to separate concerns. (Project Summary)
9. **Initialize Cursor Metrics**: In `/`, run:
   - `touch cursor_metrics.md`
   - Add a README line: `Refer to cursor_project_rules.mdc for metrics guidelines.`
   (Project Summary: IDE & AI Assistant)
10. **Setup Cursor Directory**: Create `.cursor` in `/` and inside it `touch metrics.config.mdc`. (Project Summary: IDE & AI Assistant)
11. **Validation**: Confirm `.cursor/metrics.config.mdc` and `cursor_metrics.md` exist in `/`. (Project Summary: IDE & AI Assistant)

## Phase 2: Frontend Development

12. **Initialize React App**: In `/frontend`, run:
    ```bash
    npx create-react-app . --template typescript
    ```
    (Project Summary: Tech Stack)
13. **Install UI & i18n Dependencies**: In `/frontend`, run:
    ```bash
    npm install styled-components@5.3.10 i18next@22.4.7 react-i18next@12.2.0 socket.io-client@4.6.2
    ```
    (Project Summary: Tech Stack)
14. **Create Styled-Components Theme**: Create `/frontend/src/theme.ts` with a basic light/dark theme. (Project Summary: Tech Stack)
15. **Configure i18next**: Create `/frontend/src/i18n.ts` importing `i18next` and `react-i18next`; configure English/Spanish namespaces (`en`, `es`). (Project Summary: Tech Stack)
16. **Setup Routes**: Install React Router v6: `npm install react-router-dom@6.14.0` in `/frontend`. Then create `/frontend/src/AppRoutes.tsx` defining routes for `/login`, `/events`, `/vote`. (Project Summary: App Flow)
17. **Build Login Screen Component**: Create `/frontend/src/components/LoginForm.tsx`; use styled-components for styling; add email and SMS field; use regex from Project Summary: Key Features. (Project Summary: Key Features)
18. **Validation**: Run `npm test src/components/LoginForm.test.tsx` and ensure 100% coverage on form validation. (Project Summary: Q&A)
19. **Event Creation Wizard UI**: Create `/frontend/src/components/EventWizard/Step1.tsx` through `Step4.tsx` reflecting configuration steps (Name, Timing, Visibility, Tokens). (Project Summary: Key Features)
20. **Validation**: Manually navigate through wizard in browser and confirm state persists between steps. (Project Summary: Q&A)

## Phase 3: Backend Development

21. **Initialize Backend**: In `/backend`, run:
    ```bash
    npm init -y
    npm install express@4.18.2 pg@8.10.0 jsonwebtoken@9.0.0 dotenv@16.3.1 twilio@4.17.1 @sendgrid/mail@7.16.1 socket.io@4.6.2 cors@2.8.5
    npm install -D typescript@5.1.3 ts-node@10.9.1 @types/express@4.17.19 @types/node@20.4.2
    ```
    (Project Summary: Tech Stack)
22. **Configure TypeScript**: Create `/backend/tsconfig.json` with `"target":"ES2020"`, `"module":"CommonJS"`, and `outDir":"dist"`. (Project Summary: Tech Stack)
23. **Create Server Entry**: In `/backend/src/server.ts`, set up Express app, import `cors`, `dotenv`, initialize JSON parsing, and start on port 4000. (Project Summary: App Flow)
24. **Validation**: Run `npx ts-node src/server.ts` and confirm `Server listening on port 4000` in console. (Project Summary: Tech Stack)
25. **Connect to PostgreSQL**: In `/backend/src/db.ts`, use `pg.Pool` with connection from `process.env.DATABASE_URL`. (Project Summary: Tech Stack)
26. **Database Schema**: Create `/backend/db/schema.sql`:
    ```sql
    CREATE TABLE users(
      id SERIAL PRIMARY KEY,
      phone VARCHAR(20) UNIQUE,
      role VARCHAR(10) NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );
    CREATE TABLE events(
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      start_time TIMESTAMP,
      end_time TIMESTAMP,
      mode VARCHAR(10) NOT NULL,
      host_id INT REFERENCES users(id)
    );
    CREATE TABLE votes(
      id SERIAL PRIMARY KEY,
      event_id INT REFERENCES events(id),
      user_id INT REFERENCES users(id),
      choice TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
    ```
    (Project Summary: Database)
27. **Apply Schema**: In `/backend`, run `psql $DATABASE_URL -f db/schema.sql`. (Project Summary: Database)
28. **Validation**: Connect via `psql` and run `\dt` to confirm tables exist. (Project Summary: Database)
29. **Auth Middleware**: Create `/backend/src/middleware/auth.ts` verifying JWT from `Authorization` header using `jsonwebtoken`. (Project Summary: Key Features)
30. **Validation**: Write `/backend/tests/auth.test.ts` to simulate valid/invalid tokens. Run `npm test`. (Project Summary: Q&A)
31. **SMS Endpoint**: In `/backend/src/routes/sms.ts`, implement `POST /sms/join` that uses `twilio` to send a login code. (Project Summary: SMS-based entry)
32. **Email Endpoint**: In `/backend/src/routes/email.ts`, implement `POST /email/notify` using `@sendgrid/mail`. (Project Summary: Email Provider)
33. **Voting API**: Create `/backend/src/routes/vote.ts` for `POST /events/:id/vote`. Enforce one vote per user per event. (Project Summary: Key Features)
34. **Leaderboard API**: Create `/backend/src/routes/leaderboard.ts` for `GET /events/:id/leaderboard`. Return aggregate counts. (Project Summary: Key Features)
35. **Validation**: Use `curl` to test all endpoints: `curl -X POST http://localhost:4000/events/1/vote`. Confirm correct status codes. (Project Summary: Q&A)

## Phase 4: Integration

36. **CORS Setup**: In `/backend/src/server.ts`, add `app.use(cors({ origin: 'http://localhost:3000' }));`. (Project Summary: Tech Stack)
37. **Socket.IO Sync**: In `/backend/src/server.ts`, initialize `new Server(httpServer)` and emit `vote_update` on new votes. (Project Summary: Real-time Updates)
38. **Frontend Socket Client**: In `/frontend/src/services/socket.ts`, connect to `http://localhost:4000` using `socket.io-client` and subscribe to `vote_update`. (Project Summary: Real-time Updates)
39. **Connect Login Form**: In `/frontend/src/services/auth.ts`, POST to `/backend/sms/join` and store returned JWT in `localStorage`. (Project Summary: App Flow)
40. **Event Wizard API Calls**: In `/frontend/src/api/event.ts`, implement `createEvent`, `getEvents` using `fetch` with Authorization header. (Project Summary: App Flow)
41. **Validation**: Run end-to-end test in browser: join via SMS, create event, cast vote, and observe leaderboard update in real time. (Project Summary: Q&A)

## Phase 5: Deployment

42. **AWS RDS Setup**: In AWS console, provision PostgreSQL 15.x in `us-east-1`; capture `DATABASE_URL`. (Project Summary: Hosting & Infrastructure)
43. **Store Secrets**: In AWS Parameter Store, save `DATABASE_URL`, `TWILIO_AUTH_TOKEN`, `SENDGRID_API_KEY` under `/event-vote/{env}`. (Project Summary: Security)
44. **Backend Dockerfile**: Create `/backend/Dockerfile` using Node 20.2.1, copy code, run `npm ci`, `npm run build`, and `CMD [