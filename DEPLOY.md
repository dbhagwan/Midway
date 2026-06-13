# Deploying Midway for free (Render + Neon)

Fifteen minutes, $0/month. You'll end up with a real backend URL that
the iPhone app talks to instead of demo mode.

## 1. Create the database (Neon)

1. Go to [neon.tech](https://neon.tech) → sign up (GitHub login works).
2. Create a project (call it `midway`; pick the region closest to your users).
3. On the project dashboard, find **Connection string** and copy the URI that
   looks like:
   `postgresql://user:password@ep-xxx.region.aws.neon.tech/neondb?sslmode=require`
4. Keep it handy — this is your `DATABASE_URL`. Don't commit it anywhere.

## 2. Deploy the server (Render)

1. Go to [render.com](https://render.com) → sign up with GitHub.
2. Click **New +** → **Blueprint** → select this repository.
   Render reads `render.yaml` and proposes the `midway-api` service
   (free plan, built from `Server/Dockerfile`).
3. When prompted for environment variables, paste your Neon connection
   string as `DATABASE_URL`.
4. Click deploy. First build takes ~10 minutes (it compiles Swift).
5. When it's live you get a URL like `https://midway-api.onrender.com`.
   Verify it: open `https://midway-api.onrender.com/healthz` in a browser —
   you should see `{"status":"ok"}`.

The server runs its own database migrations on boot, so Neon is set up
automatically on first start.

## 3. Point the iPhone app at it

In `project.yml`, set your URL:

```yaml
MIDWAY_API_URL: "https://midway-api.onrender.com"
```

Regenerate and build (`xcodegen generate`). With the URL set, the app
uses real accounts and the shared backend; leave it `""` to stay in
on-device demo mode.

## 4. Later, when you want push notifications

1. In your [Apple Developer account](https://developer.apple.com/account),
   create an **APNs Auth Key** (Keys → + → Apple Push Notifications service)
   and download the `.p8` file.
2. In Render → midway-api → Environment, add:
   - `APNS_KEY_P8` — the full contents of the `.p8` file
   - `APNS_KEY_ID` — the 10-character key ID
   - `APNS_TEAM_ID` — your Apple Team ID
   - `APNS_TOPIC` — `com.midway.app`
   - `APNS_ENVIRONMENT` — `production` for App Store builds
3. Redeploy. Without these the server runs fine and just logs pushes.

## Things to know on the free tier

- **Naps**: after ~15 idle minutes Render puts the free service to sleep;
  the next request takes 30–60 s while it wakes. Fine for TestFlight.
  When real users arrive, upgrade the service to Starter (~$7/mo) to keep
  it always-on.
- **Sign-in security**: Apple and Snapchat identities are verified
  server-side (Apple's public keys / Snap's `/me` endpoint). The mock
  sign-in used by development builds is blocked in production unless you
  set `MIDWAY_ALLOW_MOCK_AUTH=true` in Render's Environment — set it while
  testing without Snap/Apple credentials, and **remove it before launch**.
- **Universal links**: once you own a domain, point it at the Render
  service, replace `TEAMID` in the AASA route (`routes.swift`) and the
  associated-domains entitlement in `project.yml`, and
  `https://yourdomain/add/<username>` links will open the app.
