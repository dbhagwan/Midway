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

Requirements: Xcode 16+ (Xcode 26 for the on-device AI path), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Midway.xcodeproj
```

Build and run the `Midway` scheme on an iOS 17+ simulator or device. Run the
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
├── Services/       Auth (Snap Kit + mock), location consent, MapKit places,
│                   routing ETAs, JSON persistence
├── AI/             SuggestionEngine protocol + scoring math,
│                   HeuristicSuggestionEngine (always available),
│                   FoundationModelsEngine (iOS 26 on-device model)
├── Features/       Onboarding, Friends, Planner, Suggestions, Meetups, Profile
└── Intents/        App Intents ("Plan a Meetup" via Siri/Spotlight/Shortcuts)
```

### The AI is a decision engine, not a chatbot

Suggestion generation is a two-stage pipeline, and both stages return the same
typed `MeetupSuggestion` values:

1. **Deterministic grounding** (`HeuristicSuggestionEngine`): compute the
   travel-time-weighted midpoint, search MapKit for candidate venues, fetch
   per-participant ETAs in parallel, and score each candidate on
   **fairness** (spread + personal travel tolerances), **interest match**,
   and **budget fit** (`MeetupScoring`, fully unit-tested).
2. **On-device re-ranking** (`FoundationModelsEngine`, iOS 26+): Apple's
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

## Current MVP boundaries

- **No backend yet.** Friends are seeded demo data plus locally-added
  usernames; friend availability/consent responses are simulated from each
  friend's shared defaults. `PersistenceStore.Snapshot` and
  `AppState.simulatedResponses(for:)` mark exactly where the real API plugs in.
- Venue price levels aren't exposed by MapKit, so unknown prices score
  neutral in budget fit.
- Sign in with Apple fallback, group chat, RSVP nudges, and recurring plans
  are deliberately deferred.

## Roadmap

1. Midway backend: accounts, friend graph, push-based availability requests.
2. Real participant consent round-trip (each friend picks their own sharing
   level per plan).
3. Sign in with Apple as an alternate identity.
4. Live Activities for "leave now" nudges; calendar/RSVP follow-through.
