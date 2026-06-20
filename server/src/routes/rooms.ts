import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { makePresence } from '../realtime/presence.js';
import type { Server } from 'socket.io';

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
    const room = await db.one(
      `insert into rooms(title, icon_name, icon_color, default_ambience, visibility, livekit_room, host_id)
       values($1,$2,$3,$4,$5,$6,$7) returning *`,
      [title.trim(), iconName ?? 'brain', iconColor ?? '#6366F1', ambience ?? 'cafe', vis, slug, req.user.id],
    );
    const view = { ...room, liveCount: 0, label: '0 people focusing' };

    // Only public rooms get announced to the lobby.
    if (vis === 'public') io.to('lobby').emit('room_created', view);

    res.status(201).json(view);
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
