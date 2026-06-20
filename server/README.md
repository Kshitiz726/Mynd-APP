# OurMynd Server

Realtime + REST backend for the **Community** and **Focus Rooms** features.

## Stack
- **Node 20 + TypeScript + Express** — REST (`/api/*`)
- **Socket.IO** (+ Redis adapter) — rooms, presence, timer sync, chat, signaling bootstrap
- **Postgres** (Supabase / RDS) — durable data, via `pg-promise`
- **Redis** (Upstash / Elasticache) — live presence, room state, timer authority, socket fanout
- **LiveKit Cloud** — voice / body-doubling audio (SFU; we only mint room tokens)
- **FCM** — push notifications

All datastores are **cloud-managed**. No local sqlite, no localhost-only config.

## Architecture in one rule
Durable truth → Postgres. Live truth (who's in a room *now*, current mute, seconds
left on a timer) → Redis. A focus session writes to Postgres on **start / pause / end**
only — never on `timer_tick`. See `src/realtime/presence.ts`.

## Run it now — dev mode (zero cloud creds)
The server boots with **no credentials**: presence, focus-room timers, the
participant grid and chat fanout all run on an in-memory Redis shim, single node.
Auth trusts JWTs signed with a dev secret and builds the user from the claims.

```bash
npm install
npm run dev                 # → [config] db=in-memory(dev) redis=in-memory(dev) livekit=off(dev)
npm run smoke               # 9 realtime checks (2 clients join a room, timer, eviction)
curl localhost:8080/health  # {"ok":true,"mode":{...}}
```
What works without creds: everything realtime (sockets/presence/timers/grid).
What's disabled until you add creds:
- **REST persistence** (`/api/*`) → returns `503` until `DATABASE_URL` is set.
- **Voice** (`voice_join`) → emits `voice_unavailable` until LiveKit keys are set.

## Go live — add credentials incrementally
Each subsystem upgrades from dev fallback → cloud the moment its env var appears.

1. **Persistence** — set `DATABASE_URL` to a free Supabase Postgres URL, then:
   ```bash
   npm run migrate          # applies supabase/migrations/*.sql to your cloud DB
   ```
   Now `/api/feed`, posts, reactions, comments, chat history all persist.
2. **Multi-node scale** — set `REDIS_URL` (Upstash) to share presence across
   replicas via the Socket.IO Redis adapter.
3. **Voice / body-doubling** — set `LK_URL` / `LK_API_KEY` / `LK_API_SECRET`
   (LiveKit Cloud) to enable the audio channel.

```bash
cp .env.example .env        # fill in whichever tiers you want
npm run dev
```

## Deploy
```bash
docker build -t ourmynd-server .
docker compose up --scale api=3   # Redis adapter fans out across replicas
```
Runs anywhere containers run (Fly.io, Cloud Run, ECS, Render). Stateless — scale
horizontally; all shared state is in Redis/Postgres.

## Surface
| Transport | Path | Purpose |
|---|---|---|
| REST | `POST /api/posts`, `GET /api/feed` | create post, paginated feed (+ `?tag=study`) |
| REST | `GET /api/rooms` | active rooms + live counts + global "minds focusing" |
| REST | `GET /api/conversations` | chat list with unread badges |
| REST | `POST /api/friends/request`/`respond` | social graph |
| WS | `join_room` / `leave_room` | presence + grid |
| WS | `set_session` / `timer_control` | server-authoritative focus timer |
| WS | `toggle_mute` / `ptt_state` / `set_state` | mic + "need help" grid states |
| WS | `voice_join` → `voice_token` | LiveKit JWT for the WebRTC audio handshake |
| WS | `set_ambience` | café/rain/library/typing broadcast |
| WS | `new_reaction` | live relate/support/proud toggles |
| WS | `send_message` / `typing` | realtime chat |

See `src/realtime/socket.ts` for the full event dictionary and payloads.

## Voice / WebRTC
The Flutter client calls `voice_join`; the server verifies room membership and
mints a LiveKit `AccessToken` (audio publish/subscribe grant). The client then
connects to the LiveKit SFU with `livekit_client`. TURN/TURNS, codecs, and the
selective forwarding are all handled by LiveKit Cloud — we never relay SDP/ICE.
