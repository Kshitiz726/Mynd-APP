import { Router } from 'express';

import { requireAuth } from '../auth.js';
import { db } from '../db.js';
import { blockedIdsSql } from '../services/moderation.js';

/**
 * Report and block.
 *
 * Guideline 1.2 requires both of an app with user-generated content, and this
 * app had neither while carrying a public feed, comments, DMs and live voice.
 *
 * Deliberately blunt. A report writes a row and says thank you; a block takes
 * effect on the next read everywhere. Neither needs a moderation dashboard to
 * be worth shipping, and a reviewer testing this will tap the button, see it
 * acknowledged, and check the person is gone.
 */
const r = Router();

const TARGETS = ['post', 'comment', 'message', 'user', 'room'] as const;
const REASONS = [
  'spam', 'harassment', 'hate', 'sexual', 'violence', 'self_harm', 'other',
] as const;

type Target = (typeof TARGETS)[number];
type Reason = (typeof REASONS)[number];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ── Report something ──
r.post('/reports', requireAuth, async (req, res, next) => {
  try {
    const { targetType, targetId, reason, note, snapshot } = req.body as {
      targetType?: string; targetId?: string; reason?: string;
      note?: string; snapshot?: string;
    };

    if (!TARGETS.includes(targetType as Target)) {
      return res.status(400).json({ error: 'unknown targetType' });
    }
    if (!REASONS.includes(reason as Reason)) {
      return res.status(400).json({ error: 'unknown reason' });
    }
    if (!targetId || !UUID.test(targetId)) {
      return res.status(400).json({ error: 'bad targetId' });
    }

    // Upsert, because the unique index makes a second report a conflict rather
    // than a duplicate. Someone re-reporting with a different reason has
    // changed their mind, and that is the reason worth keeping; it also means
    // the button never fails for a person tapping it twice.
    await db.none(
      `insert into content_reports(reporter_id, target_type, target_id, reason, note, snapshot)
       values($1,$2,$3,$4,$5,$6)
       on conflict (reporter_id, target_type, target_id)
       do update set reason = excluded.reason,
                     note = excluded.note,
                     snapshot = excluded.snapshot,
                     status = 'open',
                     created_at = now()`,
      [
        req.user.id,
        targetType,
        targetId,
        reason,
        (note ?? '').slice(0, 2000) || null,
        (snapshot ?? '').slice(0, 4000) || null,
      ],
    );

    res.status(201).json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// ── Who I have blocked (and who has blocked me) ──
r.get('/blocks', requireAuth, async (req, res, next) => {
  try {
    // Only the ones I chose are listed, because this backs an "unblock" screen
    // and you cannot unblock somebody else's decision. Filtering still reads
    // both directions.
    const rows = await db.any(
      `select u.id, u.display_name, u.handle, u.initial, u.avatar_color, b.created_at
         from user_blocks b
         join users u on u.id = b.blocked_id
        where b.blocker_id = $1
        order by b.created_at desc`,
      [req.user.id],
    );
    res.json({ blocked: rows });
  } catch (err) {
    next(err);
  }
});

// ── Block ──
r.post('/blocks', requireAuth, async (req, res, next) => {
  try {
    const { userId } = req.body as { userId?: string };
    if (!userId || !UUID.test(userId)) {
      return res.status(400).json({ error: 'bad userId' });
    }
    if (userId === req.user.id) {
      return res.status(400).json({ error: 'cannot block yourself' });
    }

    await db.none(
      `insert into user_blocks(blocker_id, blocked_id) values($1,$2)
       on conflict do nothing`,
      [req.user.id, userId],
    );
    res.status(201).json({ ok: true });
  } catch (err) {
    next(err);
  }
});

// ── Unblock ──
r.delete('/blocks/:userId', requireAuth, async (req, res, next) => {
  try {
    await db.none(`delete from user_blocks where blocker_id=$1 and blocked_id=$2`, [
      req.user.id,
      req.params.userId,
    ]);
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/** Ids the caller must not see, in either direction. Used by the socket layer. */
export async function blockedIdsFor(userId: string): Promise<Set<string>> {
  const rows = await db.any<{ id: string }>(blockedIdsSql, [userId]);
  return new Set(rows.map((x) => x.id));
}

export default r;
