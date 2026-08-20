import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { makePresence } from '../realtime/presence.js';
import type { Server } from 'socket.io';

/**
 * A short, sayable join code. The alphabet drops 0/O and 1/I/L because a code
 * exists to be read off one screen and typed into another, and those pairs are
 * exactly where that goes wrong.
 */
const CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

function makeCode(len = 4): string {
  let out = '';
  for (let i = 0; i < len; i++) {
    out += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  }
  return out;
}

/**
 * Claim a code that is not already taken. Collisions are rare at 4 chars
 * (~920k combinations) but not impossible, so we retry a few times and then
 * widen to 5 rather than failing the create.
 */
async function uniqueCode(): Promise<string> {
  for (let attempt = 0; attempt < 8; attempt++) {
    const candidate = makeCode(attempt < 6 ? 4 : 5);
    const taken = await db.oneOrNone(`select 1 from rooms where code=$1`, [candidate]);
    if (!taken) return candidate;
  }
  // Vanishingly unlikely; a longer code is better than a failed request.
  return makeCode(6);
}

export function roomsRouter(io: Server) {
  const r = Router();
  const presence = makePresence(io);

  // ── Active rooms: public ones + rooms you host (so you see your own private
  //    room). Live counts come from Redis, not the durable row. ──
  r.get('/rooms', requireAuth, async (req, res) => {
    const rooms = await db.any(
      `select * from rooms
       where status='live' and (visibility='public' or host_id=$1)
       order by created_at`,
      [req.user.id],
    );
    const counts = await presence.countsFor(rooms.map((x) => x.id));
    const globalLive = await presence.globalFocusingCount();
    res.json({
      globalLive, // the "62 minds focusing right now" number
      rooms: rooms.map((x) => ({
        ...x,
        liveCount: counts[x.id] ?? 0,
        label: `${counts[x.id] ?? 0} people focusing`,
      })),
    });
  });

  // ── Create a room (Discord-style). `visibility:'public'` lists it for
  //    everyone; 'private' is join-by-link only. Broadcasts to the lobby so
  //    every client's room list updates live. ──
  r.post('/rooms', requireAuth, async (req, res) => {
    const { title, iconName, iconColor, ambience, visibility } = req.body as {
      title: string;
      iconName?: string;
      iconColor?: string;
      ambience?: string;
      visibility?: 'public' | 'private';
    };
    if (!title?.trim()) return res.status(400).json({ error: 'title required' });

    const vis = visibility === 'private' ? 'private' : 'public';
    const slug = `${String(title).toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${Date.now().toString(36)}`;
    const code = await uniqueCode();
    const room = await db.one(
      `insert into rooms(title, icon_name, icon_color, default_ambience, visibility, livekit_room, host_id, code)
       values($1,$2,$3,$4,$5,$6,$7,$8) returning *`,
      [title.trim(), iconName ?? 'brain', iconColor ?? '#6366F1', ambience ?? 'cafe', vis, slug, req.user.id, code],
    );
    const view = { ...room, liveCount: 0, label: '0 people focusing' };

    // Only public rooms get announced to the lobby.
    if (vis === 'public') io.to('lobby').emit('room_created', view);

    res.status(201).json(view);
  });

  // ── Resolve a join code to a room. ──
  //
  // This is the only door into a private room, so it deliberately does not
  // reveal anything about codes that do not resolve: same 404 whether the room
  // never existed, has ended, or is private and you guessed wrong. Otherwise
  // the endpoint is an oracle for enumerating private rooms.
  r.post('/rooms/join-by-code', requireAuth, async (req, res) => {
    const raw = (req.body as { code?: string }).code ?? '';
    // People type codes with spaces, lowercase, and the odd hyphen.
    const code = raw.replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
    if (code.length < 4) return res.status(400).json({ error: 'code too short' });

    const room = await db.oneOrNone(
      `select * from rooms where code=$1 and status='live'`,
      [code],
    );
    if (!room) return res.status(404).json({ error: 'no room with that code' });

    const counts = await presence.countsFor([room.id]);
    res.json({
      ...room,
      liveCount: counts[room.id] ?? 0,
      label: `${counts[room.id] ?? 0} people focusing`,
    });
  });

  // ── A user's session history (streaks / stats) ──
  r.get('/sessions', requireAuth, async (req, res) => {
    const rows = await db.any(
      `select * from sessions where user_id=$1 order by started_at desc limit 50`,
      [req.user.id],
    );
    res.json({ sessions: rows });
  });

  return r;
}
