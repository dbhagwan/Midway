# Midway

**Find the best place to meet, without the group chat back-and-forth.**

Midway is a Swift-native iOS app that helps friends decide where to meet by
balancing travel burden, timing, budget, and shared interests, then generating
transparent, AI-ranked suggestions on a map.

Snapchat (Login Kit) works as the login and identity layer, but Midway owns
the friend graph, interests, location consent, and meetup workflow — Snap Kit
exposes only display name, Bitmoji, and a user ID, and provides no friends
list.

## Getting started

Requirements: Xcode 26+, iOS 26 SDK, [XcodeGen](https://github.com/yonaskolb/XcodeGen).
Midway targets iOS 26 and adopts the Liquid Glass design language: prominent
glass CTAs, interactive glass interest chips in a `GlassEffectContainer`, and
a tab bar that minimizes on scroll — with system chrome (tab bars, toolbars,
sheets) picking up Liquid Glass automatically.

```sh
brew install xcodegen
xcodegen generate
open Midway.xcodeproj
```

Build and run the `Midway` scheme on an iOS 26+ simulator or device. Run the
unit tests with the `MidwayTests` target (`Cmd-U`).

**No Snap credentials needed to try it**: when `SCSDKClientId` is unset, the
app automatically uses a mock auth provider and seeds demo friends (with SF
neighborhood home areas) so the full plan → suggest → confirm flow is
demoable in the simulator.

### Enabling real Snapchat login

1. Create an app in the [Snap Kit developer portal](https://devportal.snap.com/)
   and enable Login Kit with scopes: `user.display_name`,
   `user.bitmoji.avatar`, `user.external_id`.
2. In `project.yml`, replace `SCSDKClientId: YOUR_SNAP_KIT_CLIENT_ID` with
   your client ID and register `midway://snap-kit/oauth2` as the redirect URL
   in the portal.
3. Regenerate the project (`xcodegen generate`).

## Architecture

```
Midway/
├── App/            MidwayApp (entry, URL handling), AppState, RootView
├── Models/         Core vocabulary: profiles, friends, requests, suggestions
├── Networking/     MidwayBackend protocol, RemoteBackend (API client),
│                   LocalDemoBackend (on-device demo implementation)
├── Services/       Auth (Snap Kit + mock), location consent, MapKit places,
│                   routing ETAs, JSON persistence
├── AI/             SuggestionEngine protocol + scoring math,
│                   HeuristicSuggestionEngine (always available),
│                   FoundationModelsEngine (iOS 26 on-device model)
├── Features/       Onboarding, Friends, Planner, Suggestions, Meetups, Profile
└── Intents/        App Intents ("Plan a Meetup" via Siri/Spotlight/Shortcuts)
Server/             Vapor 4 + Fluent (SQLite) backend: auth, profiles,
                    friend graph, meetup sessions & consent workflow
```

### Backend

The app talks to a `MidwayBackend` protocol with two interchangeable
implementations:

- **`LocalDemoBackend`** (default): the entire workflow on-device with seeded
  friends, simulated responses, and a demo invite — zero setup, used by the
  simulator and CI.
- **`RemoteBackend`**: URLSession client for the Vapor server in `Server/`.
  Run it with `cd Server && swift run`, then set `MIDWAY_API_URL` (in
  `project.yml` → Info.plist) to e.g. `http://localhost:8080` and regenerate.

The server owns accounts (provider login → opaque bearer token), profiles,
the friend graph, and meetup sessions: organizer creates a session with their
own consented location; invitees see it under `GET /v1/meetups/invites` and
respond with availability + a location at the precision they chose; when
everyone has answered the session flips to `ready`; the organizer's device
ranks options on-device and `POST .../confirm` writes the meetup card for all
attendees — at which point the server **erases all session locations**.
`swift test` in `Server/` covers the full workflow, including that erasure.

### The AI is a decision engine, not a chatbot

Suggestion generation is a two-stage pipeline, and both stages return the same
typed `MeetupSuggestion` values:

1. **Deterministic grounding** (`HeuristicSuggestionEngine`): compute the
   travel-time-weighted midpoint, search MapKit for candidate venues, fetch
   per-participant ETAs in parallel, and score each candidate on
   **fairness** (spread + personal travel tolerances), **interest match**,
   and **budget fit** (`MeetupScoring`, fully unit-tested).
2. **On-device re-ranking** (`FoundationModelsEngine`): Apple's
   Foundation Models framework re-ranks the grounded candidates and writes
   the one-line explanations using guided generation into `@Generable`
   structs, with a `travelTime` tool available for follow-up checks. It can
   never invent venues, and any failure degrades gracefully to the heuristic
   ranking.

The UI shows the *why*, not just the *what*: every card displays the three
scores, per-person travel minutes by transport mode, and the explanation.

### Privacy model

- Location is requested **per planning session**, never in the background.
- Users pick a sharing level each time: **exact**, **approximate (~1 km
  rounding)**, **manual** (type a place), or **none** (home neighborhood).
- Snapchat provides identity only; the friend graph and all preferences are
  Midway-owned and stored locally (JSON store, shaped like the future
  backend contract).

## Current boundaries

- Invite delivery is **polling-based** (pull-to-refresh / on-appear); APNs
  push is the next infrastructure step.
- Snap Login Kit tokens are not yet verified server-side (`AuthController`
  marks where Snap's `/me` verification belongs before production).
- Tokens are stored in UserDefaults pending a Keychain move.
- Venue price levels aren't exposed by MapKit, so unknown prices score
  neutral in budget fit.
- Sign in with Apple fallback, group chat, and recurring plans are
  deliberately deferred.

## Roadmap

1. APNs push for invites and confirmations (replace polling).
2. Server-side Snap token verification + Keychain token storage.
3. Sign in with Apple as an alternate identity.
4. Live Activities for "leave now" nudges; RSVP follow-through.
