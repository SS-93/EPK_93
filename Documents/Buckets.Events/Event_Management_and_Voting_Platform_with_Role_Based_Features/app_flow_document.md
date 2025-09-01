# App Flow Document

## Onboarding and Sign-In/Sign-Up

When a Host or Administrator first arrives at the platform, they land on the public landing page in either English or Spanish. This page explains the purpose of the Event Management & Voting Platform and offers links to Sign In or Sign Up. To create an account, the Host clicks Sign Up, enters an email address, chooses a secure password, and agrees to the terms. They then receive a confirmation email with a link to verify their address. If they ever forget their password, they click the Forgot Password link on the Sign In form, provide their email, and follow the instructions in the reset email to choose a new password. After verifying, they return to the Sign In page, enter their credentials, and are taken into the Admin Console. A Sign Out button in the top right corner of every Admin view ends the session and returns the user to the landing page.

Fans or Attendees never create a traditional username and password. Instead, they join events by texting a keyword to a short code number. They receive a SMS reply with a smart link that directs them to an inline registration page. On that page the phone number is pre-filled and optional fields for first name and email appear below two consent toggles. Once they submit, they enter the event’s vote lineup and receive a temporary token that persists in their browser session until they close or navigate away.

Artists receive an invitation link via email or from the published event page. When they follow that link, they land on a claim form specifically for the event. They enter their email (or reuse an existing one if recognized), upload an avatar, add a short bio, and paste links to their music or social channels. After submitting, their profile locks for that event and they see a confirmation screen with a link to the Artist Backstage Dashboard.

Developers sign up through the same Sign Up form as Hosts. Once verified, they log in and navigate to the Developer section of the Admin Console to generate API keys and configure webhooks. They never share these credentials publicly and may regenerate them or toggle permissions at any time.

## Main Dashboard or Home Page

After signing in, Hosts land on the Today Dashboard inside the Admin Console. A header across the top shows the platform logo, language toggle, and Sign Out link. A left sidebar lists sections labeled Events, Messaging, Analytics, Developer, and Settings. The main area displays a summary card titled Today View, highlighting active event status, votes per minute, countdown timer, and top five artists. Below that is a recent activity feed of attendee joins and vote spikes.

When Fans click their SMS smart link, they arrive at the Lineup page. This view shows a banner with the event title, cover art, and a floating Vote Meter in the bottom right corner displaying votes remaining and time until voting closes. The screen lists artist cards in a responsive grid, each with an avatar, name, and Vote button. Fans tap cards to cast votes and see a brief confirmation toast at the bottom.

Artists signing in to the Backstage Dashboard see a similar sidebar but with items labeled Profile, Votes, and Insights. The main pane shows a real-time vote count chart, a map of top-voter geographies, and a prompt to invite followers to the full Buckets platform.

Developers in the Developer section view their API credentials and webhook subscriptions. They see a list of available endpoints such as create event, invite artist, register attendee, and cast vote, along with example calls and instructions for embedding the lineup widget on external sites.

Brands with sponsorship permissions access a Sponsor Panel from the main navigation. Here they upload logos, compose a promotional message, set a promo code, and view an anonymized engagement snapshot that updates once the event closes.

## Detailed Feature Flows and Page Transitions

### Event Setup Wizard for Hosts
When a Host clicks Events in the sidebar, they see an Event List page. A Create New Event button opens the multi-step wizard. The first step, Basics, asks for title, date and time, venue, timezone, cover art image, and a toggle for Public or Private mode. Clicking Next moves to Access, where Hosts set whether anyone can join or only invitees, decide if the lineup is blurred until token verification, and review privacy and SMS opt-in language. The Voting step then appears, prompting the Host to choose a single round, specify the number of votes per attendee, set start and end times, and define a tiebreaker rule. Next, the SMS & Email step requests a keyword and short code number, plus editable reply templates for join confirmations, reminders, and closing notifications. In the Artists step, Hosts either manually add artists by email or copy a bulk invite link to share externally. A Preview step generates the final event page mockup, and clicking Publish moves the event to the Published state and makes all join, lineup, and vote links live.

### Fan Voting Flow
A Fan texts the event keyword, receives a smart link, and clicks it to open the registration page. With the phone number pre-filled, they optionally supply name and email, enable consent toggles, and tap Submit. They immediately land on the Lineup page, where they see how many votes remain and the list of artist cards. Each tap on a Vote button registers one vote, decrements the Vote Meter, and shows a micro-toast confirmation. When they have used all votes or round time expires, the Vote Meter updates to show zero and the Vote buttons disable. The page then displays a recap banner reading “You voted for X, Y, Z,” with CTAs to follow artists on social, invite friends via SMS or email, or sign up for reminders of future events. If the event is private, any attempt to refresh or revisit without the original token redirects them to an access-denied page explaining that they must use the SMS link to rejoin.

### Artist Claim and Backstage Dashboard
An Artist’s invite link brings them to the Claim Form. They confirm participation by clicking a button, complete their profile fields, and hit Submit. The form then locks, and the artist’s card on the public lineup updates to show their image and bio. The Artist Backstage Dashboard opens in a new tab, showing real-time vote counts, a geolocation heatmap of top voters, and quick links to download their vote tally or message fans. The sidebar here includes a Profile tab for one-off edits and an Insights tab where they see vote sources broken out by SMS and web deep links.

### Brand Sponsorship Flow
When a Brand user visits a Published event page and signs in as a sponsor, a Sponsor Panel appears above the lineup. They upload their logo and craft a short promotional message along with an optional discount code. During the event, they see a live summary bar of total impressions and vote counts. After voting closes, they receive an email report containing anonymized metrics such as total votes, average engagement time, and click-through rates for the promo code, with all data aggregated to preserve attendee privacy.

### Developer Integration and Embeds
Developers go to the Developer section in the Admin Console to copy their API key and webhook URL. The page lists each webhook event—vote.created, attendee.joined, artist.claimed—with toggles to enable or disable. Sample cURL requests demonstrate how to call POST /events, POST /events/:id/artists/invite, POST /events/:id/attendees/join, and POST /events/:id/votes. Below these samples, an Embed Kit tab shows a line of JavaScript that injects a secure lineup gallery widget into external sites, enforcing origin restrictions via the event token.

## Settings and Account Management

Hosts manage their personal profile and application preferences under the Settings menu in the sidebar. On the Profile tab, they can update their name, email, password, and preferred language. A Notifications tab lets them toggle email alerts for new registrations, vote threshold warnings, and daily summary digests. In the future, a Billing tab will allow Hosts to enter credit card information, view invoices, and manage subscription plans.

Developers in Settings access an API Keys page where they can regenerate credentials, view usage statistics, and rotate secrets. A Webhooks page lists all configured endpoints, shows delivery success rates, and offers retry controls for failed webhook calls.

Artists have limited Settings access. They can revisit their Claim Form before the profile lock cutoff time to make adjustments. Once locked, the form becomes read-only, and any changes require Host approval via the Admin Console’s Moderation panel.

## Error States and Alternate Paths

If a Host enters an incorrect email or password at sign in, an inline error message appears under the form field prompting them to retry or use Forgot Password. During event creation, any required field left empty triggers a red border around that input with a helper text explaining what is missing. Fans who attempt to vote after the deadline see a modal stating “Voting Closed” with a button to view results. If their join token has expired or is invalid, they land on an Access Denied page that suggests texting the event keyword again.

Network interruptions on any page display a full-screen overlay reading “Connection Lost” with a Retry button. In the Artist Backstage, if webhook delivery fails repeatedly, the Developer section flags the endpoint and shows an alert to check the destination URL. For Sponsors, if they try to upload an unsupported logo format, the upload dialog explains accepted file types and maximum size limits.

## Conclusion and Overall App Journey

A new Host starts by signing up with an email and password, verifies their account, and uses the Event Setup Wizard to configure everything from basic details to SMS reply templates. Once published, Fans join via a keyword text message, register in one step, and cast up to five votes on artist cards, then see a recap with follow-up CTAs. Artists accept invite links, fill out a claim form, and view a private dashboard showing votes and audience insights. Brands upload logos and messages in the Sponsor Panel and receive an aggregate engagement report. Developers use the Developer section to obtain API keys, subscribe to webhooks, and embed lineup widgets in partner sites. Throughout, Hosts manage profiles, preferences, and notifications in Settings, while error states ensure clear guidance when invalid data, expired tokens, or connectivity issues arise. In everyday use, Hosts monitor real-time dashboards, send targeted SMS and email campaigns, and review post-event analytics to drive engagement and plan future events—all within a seamless, role-aware experience.