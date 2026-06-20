import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';

export const sessionsRouter = Router();

sessionsRouter.post('/sessions/complete', requireAuth, async (req, res) => {
  const { roomId, completedSecs } = req.body;
  const userId = req.user.id;

  try {
    // Record the completed session. 'deep_work' is the default mode for focus rooms.
    await db.none(
      `insert into sessions (user_id, room_id, mode, duration_secs, completed_secs, status, ended_at)
       values ($1, $2, 'deep_work', 0, $3, 'completed', now())`,
      [userId, roomId, completedSecs]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error('Failed to record session:', e);
    res.status(500).json({ error: 'internal server error' });
  }
});
