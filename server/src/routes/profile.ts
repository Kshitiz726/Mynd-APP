import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { HEALTH_STATE_KEYS, hasHealthConsent } from './consent.js';

const r = Router();

/**
 * The identity a person chooses for themselves, and the state that follows
 * their account rather than the phone they installed on.
 *
 * Everything here is scoped to `req.user.id`. There is no endpoint that writes
 * another user's row, and the only readable field of someone else's is their
 * public profile (see `/users/:id` in social.ts) and their avatar.
 */

/** Largest avatar we will store, in bytes of base64. ~1MB of image. */
const MAX_AVATAR_B64 = 1_400_000;

const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp']);

/** The signed-in user's own profile, including the parts nobody else sees. */
r.get('/me', requireAuth, async (req, res, next) => {
  try {
    const u = await db.oneOrNone(
      `select id, handle, display_name, initial, avatar_color, avatar_text_color,
              email, full_name, name_chosen, current_energy, last_seen_at,
              (avatar_image is not null) as has_avatar, avatar_updated_at
       from users where id=$1`,
      [req.user.id],
    );
    if (!u) return res.status(404).json({ error: 'not found' });
    res.json({ user: withAvatarUrl(u) });
  } catch (err) {
    next(err);
  }
});

/** Change your own display name. */
r.patch('/me', requireAuth, async (req, res, next) => {
  try {
    const raw = typeof req.body?.displayName === 'string' ? req.body.displayName : '';
    const name = raw.trim().replace(/\s+/g, ' ');
    // A name has to be something a person can be addressed by and something
    // that fits in a room tile. Both ends are enforced here rather than only in
    // the client, because the client is not the only thing that can call this.
    if (name.length < 2 || name.length > 32) {
      return res.status(400).json({ error: 'name must be 2 to 32 characters' });
    }

    const u = await db.one(
      `update users set display_name=$2, name_chosen=true where id=$1
       returning id, handle, display_name, initial, avatar_color, avatar_text_color,
                 email, full_name, name_chosen,
                 (avatar_image is not null) as has_avatar, avatar_updated_at`,
      [req.user.id, name],
    );
    res.json({ user: withAvatarUrl(u) });
  } catch (err) {
    next(err);
  }
});

/** Set your own profile picture. Body: { data: base64, mime }. */
r.put('/me/avatar', requireAuth, async (req, res, next) => {
  try {
    const data = typeof req.body?.data === 'string' ? req.body.data : '';
    const mime = typeof req.body?.mime === 'string' ? req.body.mime : 'image/jpeg';
    if (!data) return res.status(400).json({ error: 'no image' });
    if (!ALLOWED_MIME.has(mime)) return res.status(400).json({ error: 'unsupported image type' });
    if (data.length > MAX_AVATAR_B64) {
      return res.status(413).json({ error: 'image too large' });
    }

    await db.none(
      `update users set avatar_image=$2, avatar_mime=$3, avatar_updated_at=now()
       where id=$1`,
      [req.user.id, data, mime],
    );
    const u = await db.one(
      `select id, display_name, initial, avatar_color, name_chosen,
              (avatar_image is not null) as has_avatar, avatar_updated_at
       from users where id=$1`,
      [req.user.id],
    );
    res.json({ user: withAvatarUrl(u) });
  } catch (err) {
    next(err);
  }
});

/** Remove your picture and go back to the coloured initial. */
r.delete('/me/avatar', requireAuth, async (req, res, next) => {
  try {
    await db.none(
      `update users set avatar_image=null, avatar_mime=null, avatar_updated_at=now()
       where id=$1`,
      [req.user.id],
    );
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

/**
 * Anyone signed in can fetch anyone's picture: it is the public face of the
 * account, shown in rooms, chat and body doubling. Served as bytes rather than
 * embedded in JSON so a list of fifty people costs fifty cache-hit image
 * requests, not fifty copies of a photo inside one response.
 */
r.get('/users/:id/avatar', requireAuth, async (req, res, next) => {
  try {
    const u = await db.oneOrNone(
      `select avatar_image, avatar_mime, avatar_updated_at from users where id=$1`,
      [req.params.id],
    );
    if (!u?.avatar_image) return res.status(404).end();

    const tag = `"${new Date(u.avatar_updated_at ?? 0).getTime()}"`;
    if (req.headers['if-none-match'] === tag) return res.status(304).end();

    res.set('Content-Type', u.avatar_mime ?? 'image/jpeg');
    res.set('ETag', tag);
    // Private: an avatar is only for signed-in callers, so no shared cache.
    res.set('Cache-Control', 'private, max-age=86400');
    res.send(Buffer.from(u.avatar_image, 'base64'));
  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Per-account state: the client's own documents (backlog, goals, habits…)
// ─────────────────────────────────────────────────────────────────────────────

/** Keys the client is allowed to park here. A closed set on purpose. */
const STATE_KEYS = new Set([
  'tasks', 'goals', 'habits', 'mood', 'streak', 'reminders', 'memory', 'focus',
]);

/**
 * Reading is deliberately not gated on health consent, where writing is.
 *
 * Withdrawing consent stops us building on this data; it does not make the
 * person's own mood history unreadable to them. Erasure is a separate,
 * explicitly offered action (DELETE /consent/health/data) precisely so that
 * "stop using it" and "delete it" stay different choices. Locking the read
 * would take the second decision away by making the data inaccessible either
 * way, and would also break the export they are entitled to.
 */
r.get('/state/:key', requireAuth, async (req, res, next) => {
  try {
    if (!STATE_KEYS.has(req.params.key)) return res.status(404).json({ error: 'unknown key' });
    const row = await db.oneOrNone(
      `select value, updated_at from user_state where user_id=$1 and key=$2`,
      [req.user.id, req.params.key],
    );
    // Absent is not an error: a new account simply has nothing parked yet.
    res.json({ value: row?.value ?? null, updatedAt: row?.updated_at ?? null });
  } catch (err) {
    next(err);
  }
});

r.put('/state/:key', requireAuth, async (req, res, next) => {
  try {
    if (!STATE_KEYS.has(req.params.key)) return res.status(404).json({ error: 'unknown key' });
    if (req.body?.value === undefined) return res.status(400).json({ error: 'no value' });

    // The health-data gate, enforced here rather than only in the app.
    //
    // The app does not offer to sync these documents without consent, but "the
    // client does not ask" is not a control - it is a convention, and it holds
    // only for the build we shipped. This is the line that actually makes the
    // policy's "we stop processing it" true, so a withdrawn account cannot
    // have its mood history or coach memory written here by an old build, a
    // queued request, or anything holding a valid token.
    if (HEALTH_STATE_KEYS.has(req.params.key) && !(await hasHealthConsent(req.user.id))) {
      return res.status(403).json({ error: 'health-data consent required', code: 'health_consent_required' });
    }
    const row = await db.one(
      `insert into user_state(user_id, key, value) values($1,$2,$3)
       on conflict (user_id, key)
       do update set value=excluded.value, updated_at=now()
       returning updated_at`,
      [req.user.id, req.params.key, JSON.stringify(req.body.value)],
    );
    res.json({ ok: true, updatedAt: row.updated_at });
  } catch (err) {
    next(err);
  }
});

/**
 * The avatar is a URL rather than bytes in every payload. Stamped with when it
 * last changed so a new picture replaces the cached one immediately instead of
 * showing the old face for a day.
 */
function withAvatarUrl(u: any) {
  const stamp = u.avatar_updated_at ? new Date(u.avatar_updated_at).getTime() : 0;
  return {
    ...u,
    avatar_url: u.has_avatar ? `/api/users/${u.id}/avatar?v=${stamp}` : null,
  };
}

export default r;
