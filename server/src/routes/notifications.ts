import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';

const r = Router();

// ── Alerts inbox: persisted notifications, newest first ──
r.get('/notifications', requireAuth, async (req, res) => {
  const rows = await db.any(
    `select id, kind, payload, read_at, created_at
     from notifications where user_id=$1
     order by created_at desc limit 100`,
    [req.user.id],
  );
  const unread = rows.filter((n) => !n.read_at).length;
  res.json({ notifications: rows, unread });
});

// ── Mark all (or a subset) read - clears the bell badge ──
r.post('/notifications/read', requireAuth, async (req, res) => {
  const { ids } = req.body as { ids?: string[] };
  if (ids?.length) {
    await db.none(
      `update notifications set read_at=now()
       where user_id=$1 and id = any($2::uuid[]) and read_at is null`,
      [req.user.id, ids],
    );
  } else {
    await db.none(
      `update notifications set read_at=now() where user_id=$1 and read_at is null`,
      [req.user.id],
    );
  }
  res.sendStatus(200);
});

export default r;
