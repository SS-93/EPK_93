# Implementation plan

## Phase 1: Environment Setup

1.  **Prevalidation**: Check if current directory is an existing project (e.g., contains `package.json` or `.git`) and skip initialization if so (**Prevalidation: Project Directory**).
2.  **Install Node.js**: Install Node.js v20.2.1 if not present (**Tech Stack: Core Tools**).
    - Validation: Run `node -v` and expect `v20.2.1`.
3.  **Install Python**: Install Python 3.11.4 if not present (**Tech Stack: Core Tools**).
    - Validation: Run `python --version` and expect `3.11.4`.
4.  **Initialize Git**: If no Git repo exists, run `git init` in project root (**Best Practice: Version Control**).
5.  **Create README**: Create `/README.md` with project title and overview (**Project Overview**).
6.  **Cursor Metrics File**: Create `/cursor_metrics.md` in root and add a comment: “Refer to `cursor_project_rules.mdc` for metrics conventions” (**Tooling: Cursor**).
7.  **Cursor MCP Directory**:
    - Create `/.cursor` directory if missing. (**Tooling: Cursor**)
    - Create `/.cursor/mcp.json` with placeholder config and add `/.cursor` to `.gitignore`. (**Tooling: Cursor**)
    - Inside `mcp.json`, insert both macOS and Windows stubs:
      ```json
      {
        "mcpServers": {
          "supabase": {
            "command": "npx",
            "args": ["-y", "@modelcontextprotocol/server-postgres", "<connection-string>"]
          }
        }
      }
      ```
    - Validation: Ensure `/.cursor/mcp.json` exists and `/.cursor` is in `/.gitignore`.
8.  **Supabase MCP Connection**: Display link for connection string: `https://supabase.com/docs/guides/getting-started/mcp#connect-to-supabase-using-mcp` and prompt user to replace `<connection-string>` in `/.cursor/mcp.json` (**Tech Stack: Supabase MCP**).
9.  **Verify MCP Status**: In Cursor, open Settings → MCP and confirm green active status (**Tech Stack: Supabase MCP**).

## Phase 2: Frontend Development

10. **Scaffold Next.js**: Run `npx create-next-app@14.0.0 frontend --typescript` to initialize Next.js 14 project (**Technical Requirements: Frontend**).
    - Note: Next.js 14 chosen per **Tool/Version Compliance**.
11. **Install UI Libraries**: In `/frontend`, run:
    ```bash
    npm install tailwindcss framer-motion
    ```
    (**Technical Requirements: Frontend**)
12. **Configure Tailwind**: Create `/frontend/tailwind.config.js` with default setup and add `./src/**/*.{js,ts,jsx,tsx}` to `content` (**Technical Requirements: Frontend**).
    - Validation: Ensure `npm run dev` compiles without errors.
13. **Global Styles**: Create `/frontend/src/styles/globals.css` with Tailwind directives (`@tailwind base; @tailwind components; @tailwind utilities;`) and import in `/frontend/src/pages/_app.tsx` (**Technical Requirements: Frontend**).
14. **LoginForm Component**: Create `/frontend/src/components/LoginForm.tsx` with email/password inputs and validation regex from **User Signup & Onboarding**.
    - Validation: Add Jest test `/frontend/__tests__/LoginForm.test.tsx` and ensure 100% coverage.
15. **MediaID Setup UI**: Create `/frontend/src/components/MediaIDSetup.tsx` to render interest-tagging controls and privacy consent toggles (**MediaID Layer**).
    - Validation: Render component in Storybook and verify controls appear.
16. **Navbar Component**: Create `/frontend/src/components/Navbar.tsx` with links: Home, Locker, Subscriptions, Dashboard (**App Flow: Navigation**).
17. **Stripe Service**: Create `/frontend/src/services/stripe.ts` that calls backend to create Checkout sessions per **Subscription Model**.
18. **Subscriptions Page**: Create `/frontend/src/pages/subscriptions.tsx` to display tiered plans and call `/api/create-checkout-session` (**Core Features: Subscription Model**).
19. **Artist Locker UI**: Create `/frontend/src/pages/artist-locker.tsx` with file-system UI & daily unlock logic based on date and **Core Features: Artist Locker**.
    - Validation: Run `npm run dev` and manually test navigation to `/artist-locker`.

## Phase 3: Backend Development

20. **Initialize Supabase**: Run `supabase init` in `/backend` to create `supabase/config.toml` (**Technical Requirements: Backend & Auth**).
21. **Auth Configuration**: In Supabase dashboard, enable Email/Password, Google, Facebook providers (**Technical Requirements: Social Logins**).
22. **Docker PostgreSQL**: In `/backend/docker-compose.yml`, add PostgreSQL 15.3 service with `POSTGRES_PASSWORD` from env (**Tech Stack: Database**).
    - Validation: `docker-compose up -d` and `psql` can connect.
23. **Define RLS Policies**: In `/backend/supabase/migrations/001_rls.sql`, add policies for row-level security per **Data and Permissions**.
24. **Auth API**: Create `/backend/api/auth.js` implementing OAuth2 token issuance and MediaID token validation middleware (**APIs & Middleware**).
25. **Subscriptions API**: Create `/backend/api/subscriptions.js` with:
    - `POST /create-checkout-session`
    - `POST /webhook` handling Stripe events (**Payment Flows**).
26. **Locker API**: Create `/backend/api/locker.js` with endpoints:
    - `GET /locker/:artistId`
    - `POST /locker/upload` using Supabase Storage (**Core Features: Artist Locker**, **Media Uploads**).
27. **Brand Campaign API**: Create `/backend/api/campaigns.js` with endpoints to create, read, and analytics for campaigns (**Core Features: Brand Campaign Integration**).
28. **MCP Table Creation**: Use Cursor MCP server to create tables in Supabase:
    - `users`, `profiles`, `subscriptions`, `content`, `preferences`, `campaigns`, `ledger` (**Tooling: Supabase MCP**, **Core Features**).
    - Validation: Run `SELECT * FROM preferences;` in psql to confirm.
29. **Realtime & Storage**: Configure Supabase Realtime for `ledger` table in `supabase/config.toml` and Storage bucket `media-uploads` (**Data Privacy & Control**).

## Phase 4: Integration

30. **API Client**: Create `/frontend/src/services/api.ts` with `fetcher` for all backend endpoints defined in **Phase 3**.
31. **CORS Setup**: In Supabase Functions config, allow origin `http://localhost:3000` (**Tech Stack: Backend & Auth**).
32. **MediaID Consent Flow**: Wire `/frontend/src/components/MediaIDSetup.tsx` to call `/api/auth/consent` and persist consent in `preferences` table (**MediaID Layer**).
33. **Stripe Front⇄Back Integration**: In `/frontend/src/pages/subscriptions.tsx`, invoke `stripeService.createCheckoutSession()` and redirect to Stripe checkout (**Payment Flows**).
34. **End-to-End Test: Signup & Subscription**: Write Cypress test in `/e2e/tests/signup-subscription.cy.ts` and ensure pass (**User Signup & Onboarding**).
35. **End-to-End Test: Locker Access**: Write Cypress test in `/e2e/tests/locker-access.cy.ts` to verify daily unlock logic (**Core Features: Artist Locker**).
36. **End-to-End Test: Campaign Creation**: Write Cypress test in `/e2e/tests/campaign.cy.ts` for brand campaign builder (**Core Features: Brand Campaign Integration**).

## Phase 5: Deployment

37. **CI Workflow**: Create `/.github/workflows/ci.yaml` to run `npm install`, `npm run build`, `npm test`, `supabase db push` (**Deployment: CI/CD**).
38. **Deploy Supabase**: Run `supabase deploy --project-ref <your-ref> --env-file /backend/.env` to deploy database and edge functions (**Deployment: Backend**).
39. **Deploy Frontend**: Connect `/frontend` to Vercel, ensure Next.js 14 build settings, and set environment variables (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_STRIPE_KEY`) (**Deployment: Frontend**).
40. **Stripe Webhooks**: Configure Stripe CLI or Dashboard to send events to `https://<your-domain>/api/webhook` and verify signature (**Payment Flows**).
41. **Analytics**: Add Google Analytics and Mixpanel SDK snippets to `/frontend/src/pages/_document.tsx` using keys from **Additional Integrations**.
42. **CDN Configuration**: Enable Cloudflare in front of Vercel domain for caching and DDoS protection (**Deployment: Infrastructure**).
43. **Soft Launch Tests**: Run full Cypress suite against staging URL and validate all critical paths (**Q&A: Pre-Launch Checklist**).
44. **KPI Dashboards**: In Supabase Studio, create dashboards for MRR, daily locker opens, campaign metrics, and opt-in rates (**KPIs**).
45. **Monitoring & Alerts**: Configure Supabase alerts and Sentry for error tracking on both frontend and backend (**Data Privacy & Control**, **Technical Requirements: Monitoring**).

*End of plan.*