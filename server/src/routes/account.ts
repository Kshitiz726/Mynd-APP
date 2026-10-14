import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth, revokeAllTokens } from '../auth.js';

/**
 * The two rights every UK consumer app has to implement in code rather than in
 * a support inbox: erasure (UK GDPR Art. 17) and portability (Art. 20).
 *
 * Neither existed. Their absence also blocked App Store review, which since
 * 2022 requires an in-app deletion route for any app that creates an account
 * (Guideline 5.1.1(v)).
 */

const r = Router();

/**
 * Everything this account owns, in one JSON document.
 *
 * Deliberately assembled by naming each table rather than by walking the
 * schema. A generic dump would silently start exporting any table added later,
 * including ones holding another user's data joined in - and an export endpoint
 * that leaks is worse than none at all. Adding a table here is a decision.
 */
r.get('/me/export', requireAuth, async (req, res, next) => {
  try {
    const uid = req.user.id;

    const [user, posts, comments, notes, state, consent, subscription, reactions] =
      await Promise.all([
        db.oneOrNone(
          `select id, handle, display_name, email, full_name, current_energy,
                  created_at, last_seen_at, health_consent_granted,
                  health_consent_decided_at, health_consent_version
             from users where id = $1`,
          [uid],
        ),
        db.manyOrNone(`select id, body, mood, created_at from posts where author_id = $1`, [uid]),
        db.manyOrNone(
          `select id, post_id, body, created_at from comments where author_id = $1`,
          [uid],
        ).catch(() => []),
        db.manyOrNone(`select * from notes where user_id = $1`, [uid]).catch(() => []),
        db.manyOrNone(`select key, value, updated_at from user_state where user_id = $1`, [uid]),
        db.manyOrNone(
          `select granted, policy_version, source, occurred_at
             from health_consent_events where user_id = $1 order by occurred_at`,
          [uid],
        ),
        db.oneOrNone(
          `select tier, status, interval, current_period_end from subscriptions where user_id = $1`,
          [uid],
        ).catch(() => null),
        db.manyOrNone(`select post_id, kind, created_at from reactions where user_id = $1`, [uid]),
      ]);

    // Messages are included, but only the ones this user wrote. The other half
    // of a conversation belongs to the other person and is not theirs to export.
    const messages = await db
      .manyOrNone(
        `select id, conversation_id, body, kind, created_at
           from messages where sender_id = $1 order by created_at`,
        [uid],
      )
      .catch(() => []);

    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Content-Disposition', `attachment; filename="ourmynd-export-${uid}.json"`);
    res.json({
      exportedAt: new Date().toISOString(),
      format: 'ourmynd.export.v1',
      note:
        'Messages you sent are included. Messages other people sent you are not, ' +
        'because they are their personal data as well as yours.',
      user,
      posts,
      comments,
      reactions,
      messages,
      notes,
      state,
      healthConsentHistory: consent,
      subscription,
    });
  } catch (err) {
    next(err);
  }
});

/**
 * Delete the account and everything belonging to it.
 *
 * Requires the caller to type their own display name back, sent as
 * `confirm`. Deletion is irreversible and reachable from a settings row, so a
 * mis-tap must not be able to reach it - this is the one place in the API where
 * an extra hoop is worth the friction.
 *
 * The heavy lifting is done by `on delete cascade` on every table that
 * references users(id), which is already how the schema is written. The
 * statements below cover the tables that reference the user by a column
 * without a cascade, and the row itself does the rest.
 */
r.delete('/me', requireAuth, async (req, res, next) => {
  try {
    const uid = req.user.id;
    const confirm = String(req.body?.confirm ?? '').trim();
    if (confirm !== req.user.displayName) {
      return res.status(400).json({
        error: 'type your display name to confirm',
        code: 'confirm_mismatch',
      });
    }

    await db.tx(async (t) => {
      // Anything not covered by a cascade, handled explicitly.
      //
      // Two of the foreign keys into users(id) have no `on delete cascade`:
      // messages.sender_id and rooms.host_id. The first was already here. The
      // second was not, and it is why this endpoint failed for anybody who had
      // ever hosted a focus room - `delete from users` raised a foreign key
      // violation, the transaction rolled back, and the account survived its
      // own deletion. Nulled rather than deleted, because a room can have other
      // people in it and losing the host is not a reason to end their session.
      for (const stmt of [
        `update rooms set host_id = null where host_id = $1`,
        `delete from user_state where user_id = $1`,
        `delete from health_consent_events where user_id = $1`,
        `delete from subscriptions where user_id = $1`,
        `delete from reactions where user_id = $1`,
        `delete from messages where sender_id = $1`,
        `delete from notes where user_id = $1`,
      ]) {
        // Each in its own savepoint, so "tolerantly" means what it says.
        //
        // These used to be `t.none(...).catch(() => undefined)`, which catches
        // the error in JavaScript and does nothing about Postgres: a failed
        // statement puts the whole transaction in the aborted state, and every
        // command after it is refused until rollback. So one missing table did
        // not skip one statement - it silently guaranteed that the final
        // `delete from users` could never run. A nested tx is a SAVEPOINT, so
        // a failure here rolls back to just before it and the outer
        // transaction stays usable.
        await t.tx((sp) => sp.none(stmt, [uid])).catch((e) => {
          console.warn('[account] skipped during delete', {
            stmt: stmt.slice(0, 40),
            code: (e as { code?: string })?.code,
          });
        });
      }
      // The account row. Every remaining foreign key cascades from here.
      await t.none(`delete from users where id = $1`, [uid]);
    });

    // It is gone, or this endpoint lied. The whole bug being fixed here is an
    // account that reported its own deletion and came back on the next
    // sign-in, so the claim is checked rather than assumed.
    const survivor = await db.oneOrNone(`select 1 from users where id = $1`, [uid]);
    if (survivor) {
      console.error('[account] delete reported success but the row is still there', {
        userId: uid.slice(0, 8),
      });
      return res.status(500).json({
        error: 'account was not deleted',
        code: 'delete_incomplete',
      });
    }

    // Belt to the cascade's braces: the row is gone, so verifyJwt would already
    // fail on "user not found", but bumping the counter first would have been
    // pointless after the delete. Called for the case where a replica or a
    // cached lookup briefly still answers.
    await revokeAllTokens(uid).catch(() => undefined);

    console.warn('[account] deleted', { userId: uid.slice(0, 8) });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

export default r;
