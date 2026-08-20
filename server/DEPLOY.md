# Deploying OurMynd online (Supabase + Fly.io) for iOS TestFlight

Goal: no more laptop backend, no local database. The server lives on Fly.io, the
data lives in Supabase, and the iOS app points at the public HTTPS URL.

The code needs **no changes** — everything is env-driven. This is all config.

---

## 1. Database — Supabase (free)

1. Create a project at https://supabase.com (free tier).
2. Connect button -> **Session pooler** -> URI. Use the pooler string (port
   `5432`, host `...pooler.supabase.com`) — it works over IPv4, unlike the
   direct `db.xxxx.supabase.co` host which is IPv6-only on the free plan and
   won't connect from most home networks:
   ```
   postgresql://postgres.PROJECTREF:YOUR_PASSWORD@aws-1-REGION.pooler.supabase.com:5432/postgres
   ```
   **Do NOT append `?sslmode=require`** — the code already sets SSL itself
   (`db.ts`, `rejectUnauthorized: false`); adding `sslmode=require` makes the new
   pg driver do strict verify-full and fails with `SELF_SIGNED_CERT_IN_CHAIN`.
   Special chars in the password must stay percent-encoded (`@`=`%40`, `#`=`%23`).
3. Apply the schema **once, from your laptop** (you already have the toolchain):
   ```bash
   cd server
   DATABASE_URL="postgresql://postgres.PROJECTREF:...pooler.supabase.com:5432/postgres" npm run migrate
   ```
   This runs all 8 files in `supabase/migrations/` against Supabase. They are the
   same migrations the local dev stack re-runs every boot, so they're safe to
   re-run. You should see `applying 0001_init.sql...` ... `migrations done`.

---

## 2. Backend — Fly.io (free allowance, stays awake)

1. Install flyctl and sign in: `fly auth signup` (or `fly auth login`).
2. From `server/`, create the app (the name in `fly.toml` must be globally
   unique — edit it if taken):
   ```bash
   cd server
   fly apps create ourmynd-server      # or: fly launch --no-deploy
   ```
3. **Set the secrets** (never commit these — Fly stores them encrypted). Fill in
   your real values:
   ```bash
   fly secrets set \
     DATABASE_URL="postgresql://postgres.PROJECTREF:...pooler.supabase.com:5432/postgres" \
     JWT_SECRET="<your Supabase JWT secret, or a long random string>" \
     GOOGLE_CLIENT_ID="<web client id>.apps.googleusercontent.com" \
     GROQ_API_KEY="<your groq key>" \
     STRIPE_SECRET_KEY="sk_live_or_test_..." \
     STRIPE_PUBLISHABLE_KEY="pk_..." \
     STRIPE_PRICE_PLUS_MONTHLY="price_..." \
     STRIPE_PRICE_PLUS_YEARLY="price_..." \
     STRIPE_PRICE_PRO_MONTHLY="price_..." \
     STRIPE_PRICE_PRO_YEARLY="price_..." \
     PUBLIC_BASE_URL="https://ourmynd-server.fly.dev"
   ```
   Optional (leave unset to stay on dev fallbacks): `REDIS_URL`, `LK_URL` /
   `LK_API_KEY` / `LK_API_SECRET`, `STRIPE_WEBHOOK_SECRET`, `FCM_SA_JSON`.
4. Deploy:
   ```bash
   fly deploy
   ```
5. Verify it's live:
   ```bash
   curl https://ourmynd-server.fly.dev/health      # -> ok
   ```
   Your public base URL is `https://<app-name>.fly.dev`. Put that exact value in
   `PUBLIC_BASE_URL` (step 3) so Stripe redirects come back to the live server,
   not localhost.

---

## 3. Point the iOS app at the live server

The app reads the backend URL from the `OURMYND_API` dart-define
(`lib/core/services/api_config.dart`). Build/run iOS with it set to the Fly URL:

```bash
flutter run -d <ios-device> \
  --dart-define=OURMYND_API=https://ourmynd-server.fly.dev \
  --dart-define=GROQ_API_KEY=<your groq key> \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>.apps.googleusercontent.com
```

For a TestFlight archive, pass the same `--dart-define`s to
`flutter build ipa`. Nothing else in the app needs to change — the localhost
references that remain (`puter_service`, `puter_host`) are the app's **own**
in-bundle asset server for the Coach WebView and are correct as-is on iOS.

---

## What is NOT localhost anymore

| Was local | Now |
|---|---|
| embedded Postgres `:5433` | Supabase `:5432` |
| laptop `npm run dev:full` | Fly.io `https://<app>.fly.dev` |
| app -> `10.0.2.2:8080` (Android emulator) | app -> `https://<app>.fly.dev` |
| Stripe redirect -> `localhost:8080` | Stripe redirect -> `PUBLIC_BASE_URL` |

`adb reverse` / `10.0.2.2` were Android-emulator-only crutches — irrelevant on
a real iPhone talking to a public HTTPS URL.
