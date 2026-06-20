# OurMynd

An **ADHD-focused productivity, wellness & community app** built with Flutter, backed
by a realtime Node + TypeScript server. OurMynd organizes the day around your *energy*
instead of priority, keeps the interface calm and low-stimulation, and adds social
focus rooms so you never have to work alone.

> Cross-platform Flutter client (Android · iOS · Web · Windows · macOS · Linux) + a
> stateless realtime backend (Socket.IO · Postgres · Redis · LiveKit).

---

## Table of contents
- [Features](#features)
- [Tech stack](#tech-stack)
- [Repository layout](#repository-layout)
- [Quick start — Flutter app](#quick-start--flutter-app)
- [Quick start — backend server](#quick-start--backend-server)
- [Architecture & key decisions](#architecture--key-decisions)
- [Build status](#build-status)
- [Configuration & secrets](#configuration--secrets)

---

## Features

- **Energy-first planning** — tasks are grouped by `EnergyLevel`, not priority, so you
  pick work that matches how you actually feel right now.
- **Low-stimulation mode** — a global toggle that desaturates the UI, flattens shadows,
  hides nudges, and tightens the backlog to reduce overwhelm.
- **Focus modes & rooms** — solo focus timers plus realtime **Focus Rooms** with
  presence, a server-authoritative timer, ambience (café/rain/library), and optional
  body-doubling **voice** channels over LiveKit.
- **Community feed** — posts, tags, reactions (relate/support/proud), comments, and
  realtime chat with media.
- **Coach (AI)** — an in-app coaching assistant running on Puter.js via a native
  WebView bridge, with chat + voice/talk mode and cross-session memory.
- **Wellness & utilities** — habits with snap-scroll tracking, notes, alarms,
  reminders, and a live-tunable accessibility profile.
- **Accessibility built in** — hyperlegible font (Atkinson Hyperlegible), reduce-motion,
  dark mode, and haptics, all wired live through settings.

## Tech stack

| Layer | Technology |
|---|---|
| Client | Flutter (Dart ≥ 3.6), Provider for state |
| Typography | Google Fonts — Fredoka (display), Lexend (body), Atkinson Hyperlegible |
| Realtime client | `socket_io_client`, `livekit_client`, `audioplayers` |
| Auth | `google_sign_in` (mobile/web) + loopback PKCE flow (desktop) |
| Coach | `flutter_inappwebview` hosting Puter.js |
| Server | Node 20 + TypeScript + Express |
| Realtime server | Socket.IO (+ Redis adapter) |
| Data | Postgres (Supabase) via `pg-promise` |
| Live state | Redis (presence, room state, timer authority) |
| Voice | LiveKit Cloud (SFU) |
| Push | FCM |

## Repository layout

```
ourmynd/
├── lib/                      # Flutter app source
│   ├── core/                 # design tokens, theme, routes, utils
│   ├── models/               # EnergyLevel, Task, Habit, FocusMode, …
│   ├── providers/            # Settings, Nav, Energy, Task, Habit
│   ├── widgets/              # reusable design-system widgets (Om*)
│   ├── services/             # client services (notifications, …)
│   ├── features/             # one folder per feature (home, focus, community, …)
│   └── main.dart
├── server/                   # Node + TypeScript realtime backend
│   ├── src/                  # routes/, realtime/, services/, models/, store/
│   ├── supabase/migrations/  # SQL migrations
│   ├── Dockerfile · docker-compose.yml
│   └── README.md             # full backend docs
├── assets/                   # audio, Puter bridge assets
├── android/ ios/ web/ windows/ macos/ linux/   # platform runners
└── pubspec.yaml
```

## Quick start — Flutter app

```bash
flutter pub get
flutter run
```

If the per-platform runner folders are missing on a fresh checkout, scaffold them once
(this wraps the existing `lib/` without overwriting it):

```bash
flutter create .
```

Fonts are loaded at runtime via `google_fonts`, so the first launch needs network;
they're cached afterward.

> Running two instances side-by-side (e.g. to test Focus Rooms)? See
> [RUN_TWO_INSTANCES.md](RUN_TWO_INSTANCES.md).

## Quick start — backend server

The server boots with **zero cloud credentials** — presence, focus-room timers, the
participant grid, and chat fanout all run on an in-memory shim:

```bash
cd server
npm install
npm run dev                 # db=in-memory redis=in-memory livekit=off
curl localhost:8080/health  # {"ok":true,...}
```

Each subsystem upgrades to cloud the moment its env var appears — set `DATABASE_URL`
(Supabase) for REST persistence, `REDIS_URL` (Upstash) for multi-node scale, and the
`LK_*` keys (LiveKit) for voice. Full details, the event dictionary, and deploy
instructions are in [server/README.md](server/README.md).

## Architecture & key decisions

- **Energy-first task model** (`EnergyLevel`) is the core organizing concept, not
  priority — matching the original prototype.
- **Low-stimulation mode** is a global concern: `SettingsProvider.lowStim` drives a
  single `LowStimFilter` (desaturation) at the shell, flattens card shadows, hides
  nudges, and tightens the backlog cap.
- **Semantic theming** travels via a `ThemeExtension` (`context.omColors`), so nothing
  hard-codes hex values; light/dark/hyperlegible are all live-switchable.
- **Backend split of truth** — durable data lives in Postgres; live data (who's in a
  room *now*, current mute, seconds left on a timer) lives in Redis. A focus session
  writes to Postgres on start/pause/end only, never on `timer_tick`.
- **Stateless server** — all shared state is in Redis/Postgres, so the API scales
  horizontally behind the Socket.IO Redis adapter.

## Build status

**Done & functional:** design system, theming (light/dark/hyperlegible), bottom-nav
shell, Home/Today (vibe + energy picker, banners, up-next, summary, day timeline,
snap-scroll habits, energy-filtered backlog with micro-steps), Focus mode selector,
Profile (all settings toggles live), realtime Focus Rooms + Community backend.

**In progress:** richer Community, Coach, Alerts, Paywall, Notes, Alarms, Reminders,
active Focus timer polish, and Onboarding/auth flows.

## Configuration & secrets

Secrets are **not** committed. The backend reads its config from `server/.env`
(ignored by git); copy the template to get started:

```bash
cp server/.env.example server/.env
```

Generated artifacts (`build/`, `.dart_tool/`, `node_modules/`, the embedded Postgres
`.pgdata/`, logs) are git-ignored and excluded from the repository.

---

Built with Flutter & a calm mind. 💙
