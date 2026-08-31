import type { Server } from 'socket.io';
import { randomUUID } from 'node:crypto';
import { redis } from '../redis.js';
import { db } from '../db.js';
import { config } from '../config.js';
import type { AuthUser } from '../auth.js';
import { scheduleEviction, cancelEviction } from './eviction.js';

/**
 * Two-tier state: live room/presence/timer truth lives here in Redis (changes
 * per second, must survive node restarts without a DB write storm). Durable
 * truth (the `sessions` row) is written to Postgres only on start / pause / end.
 *
 * Redis layout
 *   room:{id}:members       SET<userId>             liveCount = SCARD
 *   room:{id}:p:{userId}    HASH ParticipantView    grid state (TTL 120s)
 *   room:{id}:ambience      STRING ambience_kind
 *   room:{id}:music         STRING JSON RoomMusic     (TTL, see MUSIC_TTL)
 *   sess:{userId}           HASH {endsAt,pausedRemaining,running,roomId,sessionId,...}
 *   sock:{socketId}         HASH {userId, rooms}
 *   presence:global         SET<userId>             the "62 minds focusing" counter
 */

/// What a room is playing. `uri` is always a canonical `spotify:` URI - the
/// raw pasted string is normalised before it ever reaches here, so nothing
/// downstream has to cope with share links or locale-prefixed URLs.
export type RoomMusic = {
  uri: string;
  title: string | null;
  changedBy: string;
  changedAt: number;
};

const GRACE_MS = 30_000;
const PARTICIPANT_TTL = 120;

/// Room music expires; room ambience does not, and that is a bug we are not
/// repeating here. `room:{id}:ambience` is written with a bare SET and never
/// deleted, so every room that has ever existed still holds one. A day is long
/// enough that nobody in a live room loses their track, and short enough that a
/// dead room stops costing anything.
const MUSIC_TTL = 60 * 60 * 24;

/// Tolerant on read. A malformed value is treated as "no music" rather than
/// throwing: this is read on every join_room, and one bad key should not stop
/// people entering the room.
async function readMusic(
  redis: { get(key: string): Promise<string | null> },
  roomId: string,
): Promise<RoomMusic | null> {
  const raw = await redis.get(`room:${roomId}:music`);
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as RoomMusic;
    return typeof v?.uri === 'string' ? v : null;
  } catch {
    return null;
  }
}

export type MicState = 'muted' | 'speaking' | 'ptt';
export type ParticipantState = 'active' | 'inactive' | 'muted' | 'need_help';

export interface ParticipantView {
  userId: string;
  displayName: string;
  initial: string;
  avatarColor: string | null;
  state: ParticipantState;
  micState: MicState;
  session?: { task: string; mode: string; secondsRemaining: number; running: boolean };
}

// Redis hashes are string→string; flatten/parse helpers keep the view typed.
function flatten(v: ParticipantView): Record<string, string> {
  return {
    userId: v.userId,
    displayName: v.displayName,
    initial: v.initial,
    avatarColor: v.avatarColor ?? '',
    state: v.state,
    micState: v.micState,
    session: v.session ? JSON.stringify(v.session) : '',
  };
}
function parse(h: Record<string, string>): ParticipantView {
  return {
    userId: h.userId,
    displayName: h.displayName,
    initial: h.initial,
    avatarColor: h.avatarColor || null,
    state: (h.state as ParticipantState) ?? 'active',
    micState: (h.micState as MicState) ?? 'muted',
    session: h.session ? JSON.parse(h.session) : undefined,
  };
}

export function makePresence(io: Server) {
  const presence = {
    async join(roomId: string, user: AuthUser, socketId: string): Promise<ParticipantView> {
      cancelEviction(roomId, user.id); // in case they're reconnecting within grace
      const view: ParticipantView = {
        userId: user.id,
        displayName: user.displayName,
        initial: user.initial,
        avatarColor: user.avatarColor,
        state: 'active',
        micState: 'muted',
      };
      await redis
        .multi()
        .sadd(`room:${roomId}:members`, user.id)
        .hset(`room:${roomId}:p:${user.id}`, flatten(view))
        .expire(`room:${roomId}:p:${user.id}`, PARTICIPANT_TTL)
        .sadd('presence:global', user.id)
        .sadd(`user:${user.id}:rooms`, roomId) // which rooms this user is in
        .sadd(`sock:${socketId}:rooms`, roomId)
        .hset(`sock:${socketId}`, { userId: user.id })
        .exec();
      return view;
    },

    // Client pings ~every 25s; refreshes the self-healing TTL.
    async heartbeat(roomId: string, userId: string) {
      await redis.expire(`room:${roomId}:p:${userId}`, PARTICIPANT_TTL);
    },

    async isInRoom(roomId: string, userId: string): Promise<boolean> {
      return (await redis.sismember(`room:${roomId}:members`, userId)) === 1;
    },

    async patch(roomId: string, userId: string, patch: Partial<ParticipantView>) {
      const flat: Record<string, string> = {};
      if (patch.state) flat.state = patch.state;
      if (patch.micState) flat.micState = patch.micState;
      if (patch.session !== undefined) flat.session = JSON.stringify(patch.session);
      if (Object.keys(flat).length) {
        await redis.hset(`room:${roomId}:p:${userId}`, flat);
        await redis.expire(`room:${roomId}:p:${userId}`, PARTICIPANT_TTL);
      }
    },

    async snapshot(roomId: string) {
      const ids = await redis.smembers(`room:${roomId}:members`);
      const pipe = redis.pipeline();
      ids.forEach((id) => pipe.hgetall(`room:${roomId}:p:${id}`));
      const rows = (await pipe.exec()) ?? [];
      const participants = rows
        .map(([, v]) => v as Record<string, string>)
        .filter((h) => h && h.userId)
        .map(parse);
      const ambience = (await redis.get(`room:${roomId}:ambience`)) ?? 'cafe';
      return { roomId, participantCount: participants.length, ambience, participants };
    },

    async countsFor(roomIds: string[]): Promise<Record<string, number>> {
      const pipe = redis.pipeline();
      roomIds.forEach((id) => pipe.scard(`room:${id}:members`));
      const res = (await pipe.exec()) ?? [];
      const out: Record<string, number> = {};
      roomIds.forEach((id, i) => (out[id] = Number(res[i]?.[1] ?? 0)));
      return out;
    },

    async globalFocusingCount(): Promise<number> {
      return redis.scard('presence:global');
    },

    async setRoomAmbience(roomId: string, ambience: string) {
      await redis.set(`room:${roomId}:ambience`, ambience);
    },

    /// Whatever the room is currently playing, or null if nothing is.
    async roomMusic(roomId: string): Promise<RoomMusic | null> {
      return readMusic(redis, roomId);
    },

    /// Replace the room's music. Pass null to stop.
    ///
    /// Written whole rather than as a hash: it is only ever read and replaced
    /// as one unit, and a partial update would let `uri` and `title` disagree
    /// about what is playing.
    async setRoomMusic(roomId: string, music: RoomMusic | null) {
      const key = `room:${roomId}:music`;
      if (music === null) {
        await redis.del(key);
        return;
      }
      await redis.set(key, JSON.stringify(music), 'EX', MUSIC_TTL);
    },

    // ── Timer authority: store absolute end-time, derive remaining on demand ──
    async startSession(
      roomId: string,
      userId: string,
      s: { task: string; mode: string; durationSecs: number },
    ) {
      // Persist to Postgres when configured; otherwise mint a local id so the
      // in-memory timer still works (dev mode).
      const sess = config.hasDb
        ? await db.one(
            `insert into sessions(user_id, room_id, task, mode, duration_secs, status)
             values($1,$2,$3,$4,$5,'running') returning id`,
            [userId, roomId, s.task, s.mode, s.durationSecs],
          )
        : { id: randomUUID() };
      await redis.hset(`sess:${userId}`, {
        sessionId: sess.id,
        roomId,
        endsAt: String(Date.now() + s.durationSecs * 1000),
        durationSecs: String(s.durationSecs),
        running: 'true',
      });
      await presence.patch(roomId, userId, {
        session: { task: s.task, mode: s.mode, secondsRemaining: s.durationSecs, running: true },
      });
      return sess;
    },

    async timerControl(roomId: string, userId: string, action: 'pause' | 'resume' | 'end') {
      const key = `sess:${userId}`;
      if (action === 'pause') {
        const endsAt = Number(await redis.hget(key, 'endsAt'));
        await redis.hset(key, {
          running: 'false',
          pausedRemaining: String(Math.max(0, endsAt - Date.now())),
        });
        if (config.hasDb) {
          await db.none(`update sessions set status='paused' where id=$1`, [
            await redis.hget(key, 'sessionId'),
          ]);
        }
      } else if (action === 'resume') {
        const rem = Number(await redis.hget(key, 'pausedRemaining'));
        await redis.hset(key, { running: 'true', endsAt: String(Date.now() + rem) });
        if (config.hasDb) {
          await db.none(`update sessions set status='running' where id=$1`, [
            await redis.hget(key, 'sessionId'),
          ]);
        }
      } else if (action === 'end') {
        const sessionId = await redis.hget(key, 'sessionId');
        const duration = Number(await redis.hget(key, 'durationSecs'));
        const endsAt = Number(await redis.hget(key, 'endsAt'));
        const completed = Math.max(0, duration - Math.max(0, Math.round((endsAt - Date.now()) / 1000)));
        if (config.hasDb && sessionId) {
          await db.none(
            `update sessions set status='completed', ended_at=now(), completed_secs=$2 where id=$1`,
            [sessionId, completed],
          );
        }
        await redis.del(key);
      }
      const endsAt = Number((await redis.hget(key, 'endsAt')) ?? Date.now());
      const running = (await redis.hget(key, 'running')) === 'true';
      return {
        running,
        secondsRemaining: Math.max(0, Math.round((endsAt - Date.now()) / 1000)),
      };
    },

    // ── Shared removal ──
    // Take a user out of a room, recompute the live count, broadcast it to the
    // room + lobby, drop them from the global "focusing" set if they're no
    // longer in ANY room, auto-close empty user rooms, and pause a live timer.
    async evict(roomId: string, userId: string) {
      cancelEviction(roomId, userId);
      await redis
        .multi()
        .srem(`room:${roomId}:members`, userId)
        .del(`room:${roomId}:p:${userId}`)
        .srem(`user:${userId}:rooms`, roomId)
        .exec();
      const count = await redis.scard(`room:${roomId}:members`);

      // The "minds focusing" counter follows room membership, not socket state.
      if ((await redis.scard(`user:${userId}:rooms`)) === 0) {
        await redis.srem('presence:global', userId);
      }

      io.to(`room:${roomId}`).emit('participant_left', { roomId, userId, count });
      io.to(`room:${roomId}`).emit('room_count_update', { roomId, count });
      io.to('lobby').emit('room_live_update', { roomId, count });
      io.to('lobby').emit('global_focus_update', { count: await presence.globalFocusingCount() });

      // Auto-close an empty user-created room (seeded rooms have host_id null).
      if (count === 0 && config.hasDb) {
        const room = await db.oneOrNone(
          `update rooms set status='ended'
           where id=$1 and host_id is not null and status='live' returning id`,
          [roomId],
        );
        if (room) io.to('lobby').emit('room_removed', { roomId });
      }

      // Preserve focus minutes: pause the timer so it survives.
      if ((await redis.exists(`sess:${userId}`)) === 1) {
        await presence.timerControl(roomId, userId, 'pause');
      }
    },

    // ── Explicit "Leave Room" - remove immediately, no grace period. ──
    async leave(roomId: string, userId: string, socketId: string) {
      await redis.srem(`sock:${socketId}:rooms`, roomId);
      await presence.evict(roomId, userId);
    },

    // ── Socket dropped (app closed / network blip) - grey them, hold a 30s
    // grace so a reconnect can rejoin seamlessly, then evict if still gone. ──
    async handleDisconnect(socketId: string, userId: string, rooms: string[]) {
      for (const roomId of rooms) {
        await presence.patch(roomId, userId, { state: 'inactive' });
        io.to(`room:${roomId}`).emit('participant_update', {
          roomId,
          userId,
          patch: { state: 'inactive' },
        });
        scheduleEviction(roomId, userId, GRACE_MS, () => presence.evict(roomId, userId));
      }
      if (config.hasDb) {
        await db.none(`update users set last_seen_at=now() where id=$1`, [userId]);
      }
      await redis.del(`sock:${socketId}`, `sock:${socketId}:rooms`);
    },

    async rejoin(roomId: string, userId: string) {
      cancelEviction(roomId, userId);
      await presence.patch(roomId, userId, { state: 'active' });
    },
  };

  return presence;
}

export type Presence = ReturnType<typeof makePresence>;
