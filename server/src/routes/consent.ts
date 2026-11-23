import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';

/**
 * Consent to process health-related information.
 *
 * This is deliberately its own route rather than a field on /me. The privacy
 * policy says this consent is asked for separately from the Terms and is not a
 * condition of holding an account, and a boolean living inside the profile
 * endpoint would have made it just another profile setting - something the
 * sign-up path could set in passing, which is the exact thing the policy says
 * does not happen.
 *
 * See supabase/migrations/20260825000000_health_consent.sql for why the state
 * is stored twice (append-only log + denormalised current value).
 */

/**
 * The version of the published privacy policy this build asks people to agree
 * to. Bump it when the health-data section changes materially: everyone whose
 * stored consent names an older version is then treated as un-asked and is
 * prompted again, because consent to a document is consent to that document
 * and not to whatever it later becomes.
 *
 * The server owns this rather than the app so that a policy change takes
 * effect for every client at once, including the ones nobody has updated.
 */
export const PRIVACY_POLICY_VERSION = '2026-08-25';

/**
 * The version of the AI data-sharing disclosure this build asks people to
 * agree to, before anything they type reaches the third-party AI provider.
 *
 * Bump it when the disclosure changes materially - a different provider, a new
 * category of data sent - so that everyone whose agreement names an older
 * version is asked again. Owned by the server, like the policy version, so a
 * change reaches every installed client at once.
 */
export const AI_DISCLOSURE_VERSION = '2026-11-22';

/**
 * The `user_state` documents that carry health-related information.
 *
 * A deliberately narrow list. `mood` is a record of mental state over time and
 * `memory` is the coach's written picture of the person, frequently including
 * why they are struggling - both are health-related on any reading. Tasks,
 * goals, habits, streaks, reminders and focus are not: they are a to-do list
 * and its scaffolding, they are what the app is for, and the policy promises
 * that withdrawing consent does not cost access to the rest of the app.
 * Sweeping them in here because a habit *might* be medication would empty the
 * app for someone exercising a right that was supposed to be free.
 */
export const HEALTH_STATE_KEYS = new Set(['mood', 'memory']);

type ConsentRow = {
  health_consent_granted: boolean | null;
  health_consent_decided_at: Date | null;
  health_consent_version: string | null;
};

/**
 * Whether this user's health-related data may be processed right now.
 *
 * Stale consent (given against an older policy version) does not count. That
 * is the conservative reading and the only one consistent with re-asking: if
 * an out-of-date consent still gated processing, the re-ask would be cosmetic.
 *
 * Callers get a plain boolean because that is what a gate needs. Anything that
 * has to *explain* the state to a person should read the row instead.
 */
export async function hasHealthConsent(userId: string): Promise<boolean> {
  const row = await db.oneOrNone<ConsentRow>(
    `select health_consent_granted, health_consent_decided_at, health_consent_version
       from users where id = $1`,
    [userId],
  );
  if (!row) return false;
  return row.health_consent_granted === true &&
    row.health_consent_version === PRIVACY_POLICY_VERSION;
}

/** Shape the current state for the client, including why it may need re-asking. */
function describe(row: ConsentRow | null) {
  const granted = row?.health_consent_granted ?? null;
  const version = row?.health_consent_version ?? null;
  // Consent given against a superseded policy is reported as undecided, so the
  // app asks again rather than quietly relying on an agreement to old wording.
  const stale = granted === true && version !== PRIVACY_POLICY_VERSION;
  return {
    granted: stale ? null : granted,
    decidedAt: stale ? null : (row?.health_consent_decided_at ?? null),
    policyVersion: version,
    currentPolicyVersion: PRIVACY_POLICY_VERSION,
    // True when the app should present the consent screen: never asked, or
    // asked against wording that no longer stands.
    needsDecision: granted === null || stale,
  };
}

const r = Router();

/** The signed-in user's current health-data consent state. */
r.get('/consent/health', requireAuth, async (req, res, next) => {
  try {
    const row = await db.oneOrNone<ConsentRow>(
      `select health_consent_granted, health_consent_decided_at, health_consent_version
         from users where id = $1`,
      [req.user.id],
    );
    res.json(describe(row));
  } catch (err) {
    next(err);
  }
});

/**
 * Record a decision. Body: { granted: boolean, source?: 'onboarding'|'settings' }.
 *
 * `granted` is required and has no default. An endpoint that treated a missing
 * field as consent would be the bundled, pre-ticked consent the policy says we
 * do not collect, reintroduced at the API instead of in the UI.
 *
 * The policy version is taken from the server, not the request: a client
 * cannot claim someone agreed to a document that was never on their screen.
 */
r.post('/consent/health', requireAuth, async (req, res, next) => {
  try {
    const granted = req.body?.granted;
    if (typeof granted !== 'boolean') {
      return res.status(400).json({ error: 'granted must be true or false' });
    }
    const source = req.body?.source === 'settings' ? 'settings' : 'onboarding';

    // One transaction: the evidence and the gate must not disagree, and the
    // window between two bare statements is exactly where they would.
    const row = await db.tx(async (t) => {
      await t.none(
        `insert into health_consent_events (user_id, granted, policy_version, source)
         values ($1, $2, $3, $4)`,
        [req.user.id, granted, PRIVACY_POLICY_VERSION, source],
      );
      return t.one<ConsentRow>(
        `update users
            set health_consent_granted    = $2,
                health_consent_decided_at = now(),
                health_consent_version    = $3
          where id = $1
        returning health_consent_granted, health_consent_decided_at, health_consent_version`,
        [req.user.id, granted, PRIVACY_POLICY_VERSION],
      );
    });

    res.json(describe(row));
  } catch (err) {
    next(err);
  }
});

/**
 * Delete the health-related data already stored for this account.
 *
 * Offered alongside withdrawal rather than bolted onto it. Withdrawing stops
 * future processing, which is a different thing from erasing the past, and
 * some people want the first without the second - their mood history is theirs
 * and they may want to keep reading it even after telling us to stop building
 * on it. Making one imply the other would take that choice away.
 *
 * Only the documents in HEALTH_STATE_KEYS, plus the energy level cached on the
 * user row. The rest of the account is untouched, by the same reasoning that
 * keeps those keys off the list.
 */
r.delete('/consent/health/data', requireAuth, async (req, res, next) => {
  try {
    const keys = [...HEALTH_STATE_KEYS];
    const deleted = await db.tx(async (t) => {
      const rows = await t.result(
        `delete from user_state where user_id = $1 and key in ($2:csv)`,
        [req.user.id, keys],
      );
      await t.none(`update users set current_energy = null where id = $1`, [req.user.id]);
      return rows.rowCount;
    });
    res.json({ ok: true, deletedDocuments: deleted });
  } catch (err) {
    next(err);
  }
});

/** The audit trail for this account, newest first. Their own evidence, too. */
r.get('/consent/health/history', requireAuth, async (req, res, next) => {
  try {
    const events = await db.manyOrNone(
      `select granted, policy_version, source, occurred_at
         from health_consent_events
        where user_id = $1
        order by occurred_at desc
        limit 100`,
      [req.user.id],
    );
    res.json({ events });
  } catch (err) {
    next(err);
  }
});

// ============ AI DATA-SHARING CONSENT ============
//
// The coach's replies come from a third-party AI provider (Groq), so the user's
// messages leave the account to a company that is not us. 5.1.2(i) requires
// agreement before that happens. Stored and shaped like health consent, but
// kept separate because it is the floor the coach cannot run below, not the
// optional enrichment health consent governs. See the migration for why.

type AiConsentRow = {
  ai_consent_granted: boolean | null;
  ai_consent_decided_at: Date | null;
  ai_consent_version: string | null;
};

/**
 * Whether this user's messages may be sent to the third-party AI right now.
 *
 * Agreement given against a superseded disclosure version does not count, for
 * the same reason it does not for health consent: a re-ask that still honoured
 * the old answer would be cosmetic. Fails closed - any row we cannot read, or a
 * version mismatch, is "no".
 */
export async function hasAiConsent(userId: string): Promise<boolean> {
  const row = await db.oneOrNone<AiConsentRow>(
    `select ai_consent_granted, ai_consent_decided_at, ai_consent_version
       from users where id = $1`,
    [userId],
  );
  if (!row) return false;
  return row.ai_consent_granted === true &&
    row.ai_consent_version === AI_DISCLOSURE_VERSION;
}

/** Shape the current AI-consent state for the client. */
function describeAi(row: AiConsentRow | null) {
  const granted = row?.ai_consent_granted ?? null;
  const version = row?.ai_consent_version ?? null;
  const stale = granted === true && version !== AI_DISCLOSURE_VERSION;
  return {
    granted: stale ? null : granted,
    decidedAt: stale ? null : (row?.ai_consent_decided_at ?? null),
    disclosureVersion: version,
    currentDisclosureVersion: AI_DISCLOSURE_VERSION,
    needsDecision: granted === null || stale,
  };
}

/** The signed-in user's current AI data-sharing consent state. */
r.get('/consent/ai', requireAuth, async (req, res, next) => {
  try {
    const row = await db.oneOrNone<AiConsentRow>(
      `select ai_consent_granted, ai_consent_decided_at, ai_consent_version
         from users where id = $1`,
      [req.user.id],
    );
    res.json(describeAi(row));
  } catch (err) {
    next(err);
  }
});

/**
 * Record a decision. Body:
 * { granted: boolean, source?: 'coach'|'settings'|'connect'|'retry' }.
 *
 * `granted` is required and has no default, for the same reason as health
 * consent: a missing field treated as yes would be the bundled, pre-agreed
 * consent the guideline forbids, moved from the UI to the API. The disclosure
 * version is taken from the server, never the request.
 */

/**
 * Where the answer was given. An allowlist, so a client cannot write arbitrary
 * text into the audit trail, and an explicit one, so a new screen is a
 * deliberate addition here rather than something that silently lands as
 * 'coach'.
 *
 *   coach    - the gate in front of the conversation
 *   settings - the AI data screen
 *   connect  - the disclosure shown when connecting a provider, which is now
 *              the first place most people meet it
 *   retry    - a decision taken offline, reaching us on a later sync. The
 *              answer is the user's; only its arrival is delayed.
 */
const AI_CONSENT_SOURCES = ['coach', 'settings', 'connect', 'retry'] as const;
type AiConsentSource = (typeof AI_CONSENT_SOURCES)[number];

r.post('/consent/ai', requireAuth, async (req, res, next) => {
  try {
    const granted = req.body?.granted;
    if (typeof granted !== 'boolean') {
      return res.status(400).json({ error: 'granted must be true or false' });
    }
    // Falls back rather than rejecting: an older or newer client naming a
    // source we do not know must still be able to record the decision. Losing
    // a consent answer over a label would be the worse failure by far.
    const claimed = req.body?.source;
    const source: AiConsentSource =
      AI_CONSENT_SOURCES.includes(claimed) ? claimed : 'coach';

    // One transaction, so the evidence and the gate cannot disagree.
    const row = await db.tx(async (t) => {
      await t.none(
        `insert into ai_consent_events (user_id, granted, disclosure_version, source)
         values ($1, $2, $3, $4)`,
        [req.user.id, granted, AI_DISCLOSURE_VERSION, source],
      );
      return t.one<AiConsentRow>(
        `update users
            set ai_consent_granted    = $2,
                ai_consent_decided_at = now(),
                ai_consent_version    = $3
          where id = $1
        returning ai_consent_granted, ai_consent_decided_at, ai_consent_version`,
        [req.user.id, granted, AI_DISCLOSURE_VERSION],
      );
    });

    res.json(describeAi(row));
  } catch (err) {
    next(err);
  }
});

/** The AI-consent audit trail for this account, newest first. */
r.get('/consent/ai/history', requireAuth, async (req, res, next) => {
  try {
    const events = await db.manyOrNone(
      `select granted, disclosure_version, source, occurred_at
         from ai_consent_events
        where user_id = $1
        order by occurred_at desc
        limit 100`,
      [req.user.id],
    );
    res.json({ events });
  } catch (err) {
    next(err);
  }
});

export default r;
