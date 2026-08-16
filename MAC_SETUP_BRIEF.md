# OurMynd — Mac setup brief

Paste this whole file as your first message. The repo is already cloned; read
files directly rather than asking me to paste them.

## The machine
- macOS **14.0 Sonoma** (boss's Mac, accessed via TeamViewer).
- Xcode is **not** installed. The App Store only offers Xcode 26.x, which
  requires macOS 26.2, so App Store install is impossible. Do not suggest it.

## Repo
- GitHub: `https://github.com/Kshitiz726/Mynd-APP.git`
- **Use branch `home-ui-polish`** — it is the current code. `main` is 76 commits
  behind. Clone with `-b home-ui-polish`.
- Flutter app at repo root; Node/TypeScript backend in `server/`.
- Requires Flutter >= 3.27, Dart >= 3.6, Node >= 20.

## Decisions already made — do not re-litigate these

### 1. Launch target: iOS Simulator. NOT macOS desktop.
The `macos/` folder is stock Flutter scaffolding that has never been run for
this app. Concretely:
- `macos/Runner/DebugProfile.entitlements` grants `app-sandbox`, `allow-jit`,
  `network.server` — but **not** `com.apple.security.network.client`.
  `Release.entitlements` grants only the sandbox. A sandboxed Mac app without
  the network-client entitlement cannot make outbound connections, so the
  backend, Socket.IO feed, Focus Rooms, Groq, and the Puter coach WebView all
  fail (and it presents as a hang, not an error).
- `google_sign_in` has no macOS implementation. The desktop loopback OAuth
  fallback is documented in `pubspec.yaml` as Windows/Linux only, and the sole
  platform branch in the codebase (`lib/core/services/puter_service.dart:62`)
  keys on `Platform.isWindows`. macOS is unhandled.
- LiveKit voice would need microphone entitlements that are absent.

iOS is the maintained target: configured `ios/Podfile` at iOS 13.0, bundle id
`com.ourmynd.app`, a working `codemagic.yaml` that ships TestFlight builds, and
a dedicated iOS OAuth client id in the server config.

### 2. Xcode version: 15.4 (or update macOS first)
- Xcode 16.2 requires macOS **14.5+**. This Mac is on 14.0.
- Option A (preferred): System Settings -> General -> Software Update -> take
  Sonoma 14.7.x (a free minor update, stays on Sonoma), then install Xcode 16.2.
- Option B (no OS update): install **Xcode 15.4**, the newest that accepts
  macOS 14.0. It builds this project fine — deployment target is iOS 13.0.
- Either way, download the `.xip` from `developer.apple.com/download/all`
  with a free Apple ID. No paid membership needed.
- If you install Xcode 15.4, pin Flutter to 3.27.x (git clone the tag) rather
  than latest stable, which now expects Xcode 16+.

### 3. Backend scope: get the client running first, then start the backend.
The backend is **two commands** — ignore any advice that it needs Postgres,
Redis, Docker, or a Supabase signup installed locally. It does not.

## Setup sequence

```bash
# Xcode first (see above), then:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

# Toolchain (Homebrew still ships bottles for Sonoma)
brew install --cask flutter      # skip if pinning Flutter 3.27 for Xcode 15.4
brew install node cocoapods
flutter doctor

# Code
cd ~/Developer
git clone -b home-ui-polish https://github.com/Kshitiz726/Mynd-APP.git ourmynd
cd ourmynd
flutter pub get
cd ios && pod install && cd ..

# Backend, in its own terminal tab
cd ~/Developer/ourmynd/server
npm install
npm run dev:full

# App
open -a Simulator
cd ~/Developer/ourmynd
flutter run
```

In Xcode you may need to set a signing Team once under
Runner -> Signing & Capabilities. Any free Apple ID works for the Simulator.

## Why `flutter run` needs no --dart-define on the Simulator
`OURMYND_API` defaults to `http://localhost:8080` in
`lib/core/services/api_config.dart:15-17`, and the iOS Simulator shares the
Mac's network stack. Once `npm run dev:full` is up, the app finds it.

`GROQ_API_KEY` and `GOOGLE_SERVER_CLIENT_ID` are only needed for the Groq coach
and Google sign-in; add them as `--dart-define`s if those specific features are
being tested.

## What `npm run dev:full` actually does
See `server/scripts/devstack.ts`. It starts an **embedded Postgres** (downloads
a real binary, port 5433), applies all migrations in
`server/supabase/migrations/`, loads `server/supabase/seed_dev.sql`, sets
`DATABASE_URL` and `JWT_SECRET` itself, then boots the server.

`server/.env` is therefore **optional**. Redis and LiveKit default to empty in
`server/src/config.ts:8-9` and those subsystems switch off gracefully —
in-memory presence instead of Redis, no voice channels. Community feed, focus
rooms, tasks, notes, and habits all work without any .env.

`.env` only unlocks: Google sign-in (`GOOGLE_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`),
voice (`LK_*`), the paywall (`STRIPE_*`), and push (`FCM_SA_JSON`).

## Secrets — already handled, do not ask me to commit them
Two files carry the live keys and arrive by TeamViewer file transfer, never
through git:
- `server/.env` — gitignored by `server/.gitignore`
- `run-ios.local.sh` at the repo root — gitignored by the `*.local.sh` rule,
  holds the `--dart-define` values; `chmod +x` it and run it instead of a bare
  `flutter run` when testing Google sign-in or the AI coach

If either is missing, say so and I will place it. Never commit them, never echo
their contents back, and never paste them into a message.

Known gap: `GOOGLE_IOS_CLIENT_ID` is blank because no iOS OAuth client exists
yet. Google sign-in on iOS will fail until one is created in Google Cloud
Console (OAuth client ID -> iOS, bundle `com.ourmynd.app`). Everything else
works meanwhile — do not treat it as a broken build.

## What the app is
ADHD-focused productivity, wellness and community app. Plan the day by *energy*
rather than priority, in a deliberately low-stimulation UI. Feature folders live
in `lib/features/`: home, schedule, focus (solo timers + realtime Focus Rooms
with presence, server-authoritative timer, ambience, LiveKit voice), community
(feed, reactions, comments, chat), coach (AI via Puter.js in a WebView bridge),
memory, notes, alarms, reminders, notifications, profile, paywall, auth, splash,
shell. State is Provider, one provider per domain in `lib/providers/`.
