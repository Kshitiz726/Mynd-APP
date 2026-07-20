# Run two instances with real Google sign-in + a shared Focus Room

This walks you from zero to **two browser windows, each logged in with a real
Google account, joining the same Focus Room, muted by default, seeing each
other live, with time spent recorded in the database.**

There are two one-time credentials to create (both free): a Google **Web**
OAuth Client ID. (Video/camera is intentionally off - "see others" = the live
presence grid; voice via LiveKit is optional and not required for this.)

---

## 1. Create a Google OAuth **Web** Client ID  (~3 min, free)

1. Go to <https://console.cloud.google.com/> → create/select any project.
2. **APIs & Services → OAuth consent screen** → choose **External** → fill the
   app name + your email → **Save**. Under **Test users**, add the Google
   accounts you'll log in with (both of them).
3. **APIs & Services → Credentials → Create Credentials → OAuth client ID**.
   - Application type: **Web application**.
   - **Authorised JavaScript origins** - add exactly:
     - `http://localhost:5000`
   - Click **Create**. Copy the **Client ID** (ends in
     `.apps.googleusercontent.com`).

> We pin the web app to port **5000** so the origin above stays valid. If you
> use a different port, add that origin too.

## 2. Paste the Client ID in two places

**a) `web/index.html`** - replace the placeholder:
```html
<meta name="google-signin-client_id" content="YOUR_WEB_CLIENT_ID.apps.googleusercontent.com">
```

**b) `server/.env`** - create the file (copy from `.env.example`) and set at
least:
```
GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```
`DATABASE_URL` is **not** needed for local runs - `npm run dev:full` starts a
real embedded Postgres for you.

## 3. Start the backend (real DB, real Google verification)

```bash
cd server
npm install          # first time only
npm run dev:full
```
Wait for: `[config] db=cloud … google-auth=on` and
`listening on :8080`. Leave it running.

## 4. Run the app on a fixed port

```bash
flutter pub get      # first time only
flutter run -d web-server --web-port 5000 --dart-define=OURMYND_API=http://localhost:8080
```

## 5. Open two instances

- Open **`http://localhost:5000`** in **two separate browser windows**.
  Easiest: one normal Edge/Chrome window + one **Incognito/InPrivate** window
  (so they don't share the Google session).
- In each window: **Continue with Google** → pick a **different** Google
  account in each.
- Both land on the app. Go to the **Community → Rooms** tab and **Join** the
  same room in both windows.

You'll see:
- Each instance **joins muted** (mic-off badge on your tile).
- The other person's avatar tile appears live in the grid the moment they join.
- An **elapsed** stopwatch (counts up - this is the "time spent", not a
  countdown).
- On **Leave Room**, the elapsed seconds are written to the `sessions` table.

## 6. Verify the time was recorded in the database

With `npm run dev:full` still running, in another terminal:
```bash
cd server
node --import tsx -e "import('./src/db.js').then(async ({db})=>{const r=await db.any('select user_id, room_id, completed_secs, ended_at from sessions order by ended_at desc limit 10'); console.table(r); process.exit(0);})"
```
You'll see one row per room you left, with `completed_secs` = time spent.

---

## How it works (what changed)

| Piece | File | What it does |
|---|---|---|
| Real Google sign-in (web) | `lib/features/auth/login_screen.dart` | `GoogleSignIn().signIn()` → gets the Google **ID token** |
| Web client id | `web/index.html` | `google-signin-client_id` meta tag |
| Token exchange | `lib/core/services/api_client.dart` → `authWithGoogleIdToken` | POSTs the ID token to the server |
| Server verify + user creation | `server/src/auth.ts` → `POST /api/auth/google` | Verifies the Google token with `google-auth-library`, upserts the user (keyed by email), mints our 30-day JWT |
| Muted by default | `lib/providers/focus_room_provider.dart:93` | `toggleMute(roomId, true)` on join |
| Live presence grid | `lib/features/focus/focus_room_screen.dart` | Socket.IO `participant_joined/left` |
| Time recording | `focus_room_provider.dart` `leaveRoom()` → `/api/sessions/complete` | Inserts elapsed seconds into `sessions` |

## Troubleshooting

- **"Login failed: No ID token returned from Google"** - the Client ID in
  `web/index.html` is missing/wrong, or `http://localhost:5000` isn't an
  authorised JavaScript origin, or you're not on port 5000.
- **"GOOGLE_CLIENT_ID not configured on the server"** - set it in `server/.env`
  and restart `npm run dev:full`.
- **`EADDRINUSE :8080` / Postgres lock on start** - an old server is still
  running. Kill stray `node` / `postgres.exe`, then start again.
- **Both windows show the same user** - they're sharing a Google session; use
  an Incognito/InPrivate window for the second one and pick a different account.
</content>
</invoke>
