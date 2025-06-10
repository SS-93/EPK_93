# Frontend Guideline Document

This document outlines the frontend setup for **Bucket & MediaID**, our digital engagement platform for artists, fans, and brands. It’s written in everyday language so anyone can understand how the frontend works and how to build on it.

---

## 1. Frontend Architecture

### Overview
- We use **React** (create-react-app or Vite) as our core framework. It gives us a component-based structure that’s easy to scale.
- **Tailwind CSS** handles styling with utility classes—no need for huge CSS files.
- **Framer Motion** adds smooth, lightweight animations.
- **Supabase** powers authentication, file storage, and real-time data feeds.
- **Stripe Checkout** is integrated for subscription payments.
- We’ll connect to our backend APIs (Supabase, MediaID) via secure HTTPS calls, using OAuth2 tokens.

### Scalability & Maintainability
- **Component-based** design: small, reusable pieces (buttons, cards, pages) that can be added or replaced independently.
- **Folder conventions** (see Component Structure) keep code organized as the app grows.
- **Utility-first CSS** (Tailwind) reduces custom styles and avoids conflicts.
- **Code splitting** and **lazy loading** (via React.lazy) keep initial load times fast.
- **Context API** and/or **React Query** ensure data is fetched and shared cleanly.

## 2. Design Principles

1. **Usability**: Interfaces must be simple to navigate. Icons, buttons, and interactions are clearly labeled.
2. **Accessibility**: We follow WCAG guidelines—use semantic HTML, proper color contrast, keyboard navigation, and `aria-` attributes where needed.
3. **Responsiveness**: The app adapts seamlessly from mobile to desktop. We use Tailwind’s responsive utilities (`sm:`, `md:`, `lg:`) to adjust layouts.
4. **Consistency**: UI elements look and behave the same everywhere—buttons share the same hover states, typography scales consistently.
5. **Performance**: Fast load times and smooth animations. We avoid heavy libraries and large assets.

**How we apply these:**
- All interactive elements have `:focus` and `:hover` states.
- Pages are tested on screens from 320px to 1920px.
- We use semantic tags (`<nav>`, `<main>`, `<header>`) for structure.

## 3. Styling and Theming

### Styling Approach
- **Tailwind CSS** for utility-first styling, backed by a custom configuration (`tailwind.config.js`).
- No BEM or SMACSS; utility classes handle most cases. For more complex components, we use `@apply` in our own `.css` files.

### Theming
- We have a **dark, minimalist** theme inspired by a black index aesthetic. Light mode is optional but can be toggled via a simple class on `<body>`.
- **Glassmorphism panels** in artist lockers: semi-transparent backgrounds with subtle blur.

### Visual Style
- Flat, modern look with gentle glass effects.
- Light animations on hover and page transitions (Framer Motion).

### Color Palette
- Primary background: `#000000` (black)
- Secondary background: `#111111` / `#1A1A1A`
- Text: `#FFFFFF` (white) / `#DDDDDD`
- Accent 1: `#FFC600` (yellow – buttons, highlights)
- Accent 2: `#1DB954` (green – success states)
- Alerts: `#FF4500` (red – errors)
- Glass panel bg: `rgba(255, 255, 255, 0.05)` with `backdrop-filter: blur(10px)`

### Typography
- **Font**: Inter (system-ui, sans-serif fallback)
- **Sizing scale**: 0.875rem, 1rem, 1.125rem, 1.25rem, 1.5rem
- **Line height**: 1.4 for body text, 1.2 for headings

## 4. Component Structure

We follow a **component-based** architecture with clear folder conventions:

src/components/
  ├── atoms/         // Buttons, Inputs, Icons
  ├── molecules/     // FormGroups, CardItems, NavLinks
  ├── organisms/     // NavBar, Footer, LockerGrid
  ├── templates/     // Page layouts (e.g., AuthLayout, DashboardLayout)
  └── pages/         // Route components (e.g., /login, /artist, /brand)

### Reuse & Organization
- **Atoms**: smallest building blocks (e.g., `<Button />`).
- **Molecules**: combinations of atoms (e.g., `<SearchInput />`).
- **Organisms**: self-contained UI sections (e.g., `<LockerItem />`).
- **Templates**: arrange organisms into page scaffolds.
- **Pages**: finalize data fetching and pass props down.

This structure keeps things predictable and easy to navigate.

## 5. State Management

### Approach
- **React Context** + `useReducer` for global state (user session, theme toggle).
- **React Query** for server data: artists, lockers, subscriptions, analytics. It handles caching, background updates, and request deduplication.
- **Supabase hooks** (`useUser`, `useSubscribe`, `useStorage`) for auth and real-time.

### Data Flow
- Components call React Query hooks to fetch data. Cached data is shared across pages.
- Mutations (e.g., new subscription) use React Query’s `useMutation` and invalidate relevant queries.
- Context stores UI state (dark mode, drawer open/close).

## 6. Routing and Navigation

- **React Router v6** manages client-side routing.
- Routes defined in `src/App.jsx`:
  - `/` → Landing page
  - `/signup`, `/login` → Auth flow
  - `/onboarding` → Interests & privacy
  - `/artist/*` → Artist dashboard & locker
  - `/brand/*` → Brand dashboard & campaigns
  - `/fan/*` → Fan home & locker
  - `/public` → Public stats
- Nested routes for sub-pages (e.g., `/artist/locker/upload`).
- **Protected routes** wrap with an `<AuthGuard>` that redirects unauthorized users to `/login`.
- **Navigation bars** and side menus live in organism components and adjust links based on role.

## 7. Performance Optimization

1. **Code Splitting**: Use `React.lazy` + `Suspense` for large pages (dashboards, onboarding).
2. **Lazy Load Images/Media**: `loading="lazy"` on `<img>` and dynamic import for audio/video players.
3. **Tree Shaking**: Tailwind’s purge step removes unused CSS.
4. **Asset Optimization**: Compress images via build-time scripts; use modern formats (WebP) where possible.
5. **Memoization**: `React.memo` and `useMemo` for heavy components.
6. **Avoid Overfetching**: React Query’s stale time and cache time tuned to reduce repetitive calls.

These steps ensure quick initial loads and smooth interactions.

## 8. Testing and Quality Assurance

### Unit Tests
- **Jest** + **React Testing Library** for components and hooks.
- Test states: loading, success, error for data hooks.

### Integration Tests
- Combine components with mocked providers (Router, QueryClient, Supabase).
- Verify flows: login → MediaID setup → subscription.

### End-to-End Tests
- **Cypress** for user journeys:
  - Signup and onboarding
  - Uploading content to the locker
  - Subscribing via Stripe
  - Brand campaign creation

### Linting & Formatting
- **ESLint** (with React and accessibility plugins).
- **Prettier** for consistent code style.
- **Husky** + **lint-staged** to run checks on pre-commit.

## 9. Conclusion and Overall Frontend Summary

We’ve built a **scalable**, **maintainable**, and **performant** frontend using React, Tailwind CSS, and Framer Motion. Key takeaways:

- **Clear architecture** with components organized by atomic design.
- **Strong design principles**: accessible, responsive, consistent.
- **Modern styling**: dark theme, glassmorphism, utility-first CSS.
- **Efficient state and data handling** via Context, React Query, and Supabase hooks.
- **Fast, optimized** user experience through code splitting and asset management.
- **Robust QA** with unit, integration, and E2E tests.

This setup aligns with our goals to empower artists, engage fans daily, and offer brands precise targeting—while respecting user privacy via MediaID. With these guidelines, any frontend developer can confidently build, maintain, and extend the platform.