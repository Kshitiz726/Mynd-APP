import { Router } from 'express';
import { z } from 'zod';
import { config } from '../config.js';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { billingStore, isPremium, type Tier } from '../services/billing.js';
import { hasAiConsent } from './consent.js';

/**
 * The coach model, proxied.
 *
 * Two findings meet here, and one change closes both.
 *
 * The Groq key used to be compiled into the app with `--dart-define`, which
 * makes it a constant in the Dart snapshot and recoverable with `strings` from
 * any installed copy. There is no way to ship a provider key to a device and
 * keep it secret; the only fix is for the device never to hold one. So the key
 * stays here and the app talks to us instead.
 *
 * The free-tier message cap was a counter in SharedPreferences, which meant it
 * was advice rather than a limit - clearing app data reset it, and the server
 * never saw a coach message at all so it could not have enforced anything.
 * Now every turn passes through this route, the count lives in the database,
 * and the entitlement it is checked against is the server-held one.
 */

const r = Router();

const GROQ_ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';

/**
 * Coaching messages per WEEK, by tier. null means uncapped.
 *
 * Weekly rather than daily, and this is the point rather than a bigger number:
 * a daily cap punishes exactly the use this app is for. Someone with ADHD does
 * not need five messages every day - they need forty on the bad Tuesday and
 * none for the rest of the week. A daily bucket refuses them on the one day
 * they actually needed the thing, then expires unused for six days.
 *
 * Only conversation is metered. The Feed, the scheduling and every other piece
 * of the app's own reasoning go through /coach/extract, which is deliberately
 * unmetered: those are the app talking to itself, and charging a person's
 * conversation budget for the app doing its own housekeeping is indefensible.
 *
 * Matches kCoachWeeklyLimit in the app; this copy is the authoritative one.
 */
const WEEKLY_LIMIT: Record<Tier, number | null> = {
  free: 200,
  plus: 1000,
  pro: null,
};

/**
 * Models the app is allowed to ask for.
 *
 * An allow-list rather than passing the client's string through: without it,
 * whoever holds a session token chooses which model our key pays for, which is
 * a billing hole rather than a data one but a hole all the same.
 */
const ALLOWED_MODELS = new Set(['openai/gpt-oss-120b', 'openai/gpt-oss-20b']);

const CompletionRequest = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(['system', 'user', 'assistant']),
        // Generous, but bounded. Unbounded input is somebody else's token bill.
        content: z.string().max(24_000),
      }),
    )
    .min(1)
    .max(60),
  model: z.string().refine((m) => ALLOWED_MODELS.has(m), 'unsupported model'),
  stream: z.boolean().optional(),
  max_tokens: z.number().int().positive().max(4096).optional(),
  temperature: z.number().min(0).max(2).optional(),
  reasoning_effort: z.enum(['low', 'medium', 'high']).optional(),
});

/**
 * Today's count for this user, in their own day.
 *
 * The date comes from the client's IANA timezone where it sends one, because a
 * cap that resets at UTC midnight resets mid-evening in Auckland and mid-
 * afternoon in Los Angeles. It is only ever used to name a bucket, so a
 * client lying about it can at best hand itself one extra day's boundary - not
 * a way around the limit.
 */
function dayKey(tz: string | undefined): string {
  try {
    if (tz) return new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(new Date());
  } catch {
    /* unknown zone - fall through to UTC */
  }
  return new Date().toISOString().slice(0, 10);
}

/**
 * The week the user is currently in, named by its Monday as `YYYY-MM-DD`.
 *
 * A real date, because `coach_usage.day` is a DATE column. The first version of
 * this wrote an ISO week label like `2026-W39` into it, which Postgres rejected
 * outright: every meter call answered 500, the app caught it as a generic
 * failure, and the chat said "something went wrong" with no way to tell that
 * the cause was a type error in here. Type-checking the TypeScript does not
 * type-check the column.
 *
 * Naming the week by its Monday keeps the column a date, needs no migration and
 * no schema change, and reads correctly in the table.
 *
 * It does share a row with the old daily counter for any Monday that already
 * had usage, so a week in progress at the moment of this change starts with
 * that Monday's messages already counted. That is a one-off, it is bounded by
 * the old daily cap, and those messages genuinely were sent in this week.
 *
 * Weeks start Monday, matching how the rest of the app talks about a week.
 */
function weekKey(tz: string | undefined): string {
  const local = dayKey(tz); // YYYY-MM-DD in the user's own zone
  const [y, m, d] = local.split('-').map(Number);
  // Noon UTC, so a date built from a local calendar date cannot slip a day.
  const dt = new Date(Date.UTC(y, m - 1, d, 12));
  const dayNum = (dt.getUTCDay() + 6) % 7; // Monday = 0
  dt.setUTCDate(dt.getUTCDate() - dayNum);
  return dt.toISOString().slice(0, 10);
}

/** When the current week's allowance resets, for the app to show. */
function weekResetsAt(tz: string | undefined): string {
  const local = dayKey(tz);
  const [y, m, d] = local.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d, 0, 0, 0));
  const dayNum = (dt.getUTCDay() + 6) % 7; // Monday = 0
  dt.setUTCDate(dt.getUTCDate() + (7 - dayNum));
  return dt.toISOString();
}

/** The tier's weekly allowance, or null when uncapped. */
function limitFor(tier: Tier): number | null {
  return WEEKLY_LIMIT[tier] ?? WEEKLY_LIMIT.free;
}

async function usageIn(userId: string, day: string): Promise<number> {
  if (!config.hasDb) return 0;
  const row = await db.oneOrNone(
    `select count from coach_usage where user_id = $1 and day = $2`,
    [userId, day],
  );
  return row?.count ?? 0;
}

async function bumpUsage(userId: string, day: string): Promise<void> {
  if (!config.hasDb) return;
  await db.none(
    `insert into coach_usage (user_id, day, count) values ($1, $2, 1)
     on conflict (user_id, day) do update set count = coach_usage.count + 1`,
    [userId, day],
  );
}

/**
 * Spend one coaching turn.
 *
 * The coach conversation is generated by Puter inside a WebView, using the
 * user's own Puter account, so it never passes through this server and cannot
 * be metered by proxying it the way /coach/completions meters Groq. That is why
 * the cap needs an endpoint of its own: generation stays on the client, but the
 * *entitlement* to generate is decided here.
 *
 * Check and increment happen in one statement so two rapid turns cannot both
 * read "4 used" and both proceed. The insert returns the post-increment count,
 * and the decision is made on that.
 */
r.post('/coach/turn', requireAuth, async (req, res, next) => {
  try {
    const tz = req.headers['x-timezone'] as string | undefined;
    const week = weekKey(tz);
    const sub = await billingStore.get(req.user.id);
    const premium = isPremium(sub);
    const tier: Tier = premium ? sub.tier : 'free';
    const limit = limitFor(tier);

    if (!config.hasDb) {
      // Dev without a database: no meter to keep, so allow the turn rather
      // than blocking local work on infrastructure that is not running.
      return res.json({
        allowed: true, premium, tier, used: 0, limit, remaining: null,
        resetsAt: weekResetsAt(tz),
      });
    }

    if (limit === null) {
      // Still counted, so usage is visible, but never refused.
      await bumpUsage(req.user.id, week);
      return res.json({
        allowed: true, premium, tier, limit: null, remaining: null,
        resetsAt: weekResetsAt(tz),
      });
    }

    const row = await db.one(
      `insert into coach_usage (user_id, day, count) values ($1, $2, 1)
       on conflict (user_id, day) do update set count = coach_usage.count + 1
       returning count`,
      [req.user.id, week],
    );

    if (row.count > limit) {
      // Over budget. The row was already incremented, which is deliberate:
      // leaving it means a client retrying in a loop cannot walk the counter
      // back down, and the count is only ever compared against the limit.
      return res.status(402).json({
        allowed: false,
        code: 'coach_limit_reached',
        premium,
        tier,
        used: limit,
        limit,
        remaining: 0,
        resetsAt: weekResetsAt(tz),
      });
    }

    res.json({
      allowed: true,
      premium,
      tier,
      used: row.count,
      limit,
      remaining: Math.max(0, limit - row.count),
      resetsAt: weekResetsAt(tz),
    });
  } catch (err) {
    next(err);
  }
});

/** What the app shows on the composer without spending a turn to find out. */
r.get('/coach/quota', requireAuth, async (req, res, next) => {
  try {
    const tz = req.query.tz as string | undefined;
    const week = weekKey(tz);
    const [used, sub] = await Promise.all([
      usageIn(req.user.id, week),
      billingStore.get(req.user.id),
    ]);
    const premium = isPremium(sub);
    const tier: Tier = premium ? sub.tier : 'free';
    const limit = limitFor(tier);
    res.json({
      premium,
      tier,
      used,
      limit,
      remaining: limit === null ? null : Math.max(0, limit - used),
      resetsAt: weekResetsAt(tz),
    });
  } catch (err) {
    next(err);
  }
});

/**
 * One coaching turn.
 *
 * Streams when asked to, because the app renders tokens as they arrive and a
 * blocking call would turn a live conversation into a forty-second wait. The
 * upstream SSE body is piped through untouched so the client's existing parser
 * did not have to change.
 */
r.post('/coach/completions', requireAuth, async (req, res, next) => {
  try {
    if (!config.groqApiKey) {
      return res.status(503).json({ error: 'coach is not configured on the server' });
    }

    // The permission gate, enforced where the data actually leaves. The app
    // asks before the first turn, but the app is not the thing that can be
    // trusted to - a modified client, or a direct call, would skip the screen
    // and not the send. So the send itself is refused here when there is no
    // agreement on file. Only where there is a database to hold the record:
    // dev without one has no users table to consult and no real provider key
    // either, so there is nothing to gate.
    if (config.hasDb && !(await hasAiConsent(req.user.id))) {
      return res.status(403).json({
        error: 'ai data-sharing consent required',
        code: 'ai_consent_required',
      });
    }

    const parsed = CompletionRequest.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'bad request', detail: parsed.error.issues[0]?.message });
    }
    const body = parsed.data;

    // ── The cap, enforced where it cannot be edited ──
    const tz = req.headers['x-timezone'] as string | undefined;
    const week = weekKey(tz);
    const sub = await billingStore.get(req.user.id);
    const tier: Tier = isPremium(sub) ? sub.tier : 'free';
    const limit = limitFor(tier);
    if (limit !== null) {
      const used = await usageIn(req.user.id, week);
      if (used >= limit) {
        return res.status(402).json({
          error: 'weekly message limit reached',
          code: 'coach_limit_reached',
          limit,
          tier,
          resetsAt: weekResetsAt(tz),
        });
      }
    }

    // Counted before the call, not after. A turn that fails upstream is worth
    // more to a user as a retry than a free message is worth to us, but
    // counting afterwards means a client that hangs up mid-stream never gets
    // counted at all - which is the whole cap, bypassed by disconnecting.
    await bumpUsage(req.user.id, week);

    const upstream = await fetch(GROQ_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.groqApiKey}`,
      },
      body: JSON.stringify(body),
      // Generous: a long reasoning turn legitimately takes a while. Bounded
      // anyway, so a hung upstream cannot hold the connection forever.
      signal: AbortSignal.timeout(120_000),
    });

    if (!upstream.ok || !upstream.body) {
      const detail = await upstream.text().catch(() => '');
      console.error('[coach] upstream error', upstream.status, detail.slice(0, 300));
      // The upstream body can name the model and the account; it is not passed
      // through to the client.
      return res.status(502).json({ error: 'the coach is unavailable right now' });
    }

    if (body.stream) {
      res.setHeader('Content-Type', 'text/event-stream');
      res.setHeader('Cache-Control', 'no-cache');
      res.setHeader('Connection', 'keep-alive');
      // Proxies that buffer would defeat the point of streaming.
      res.setHeader('X-Accel-Buffering', 'no');

      const reader = upstream.body.getReader();
      // If the client goes away mid-stream, stop pulling from upstream rather
      // than reading the whole completion into a socket nobody is holding.
      let aborted = false;
      res.on('close', () => {
        aborted = true;
        reader.cancel().catch(() => undefined);
      });

      for (;;) {
        const { done, value } = await reader.read();
        if (done || aborted) break;
        res.write(Buffer.from(value));
      }
      return res.end();
    }

    const json = await upstream.json();
    res.json(json);
  } catch (err) {
    next(err);
  }
});

/**
 * The day's motivation lines.
 *
 * Metered separately from the conversation, and that separation is the whole
 * reason this route exists. Motivation used to go through /coach/completions,
 * which meant a feature the user never asked for spent the five daily messages
 * they DID ask for: two mood changes and the coach was refusing to talk. Worse,
 * it failed silently into a small written bank, so the app appeared to be
 * ignoring the mood entirely rather than to be out of budget.
 *
 * Its own generous cap rather than no cap: this is still our key paying for
 * somebody else's tokens, and an unmetered completions endpoint behind a
 * session token is a free LLM proxy for anyone who reads the app's traffic.
 * The model and the token ceiling are fixed here rather than taken from the
 * client for the same reason.
 */
const FREE_MOTIVATION_LIMIT = 30;

const MOTIVATION_MODEL = 'openai/gpt-oss-20b';

const MotivationRequest = z.object({
  messages: z
    .array(
      z.object({
        role: z.enum(['system', 'user']),
        content: z.string().max(8_000),
      }),
    )
    .min(1)
    .max(4),
  // The client asks for spread, not for a different model. Bounded well below
  // the API's ceiling: past about 1.3 the lines stop being sentences.
  temperature: z.number().min(0).max(1.3).optional(),
});

async function motivationUsageToday(userId: string, day: string): Promise<number> {
  if (!config.hasDb) return 0;
  const row = await db.oneOrNone(
    `select count from motivation_usage where user_id = $1 and day = $2`,
    [userId, day],
  );
  return row?.count ?? 0;
}

r.post('/coach/motivation', requireAuth, async (req, res, next) => {
  try {
    if (!config.groqApiKey) {
      return res.status(503).json({ error: 'not configured on the server' });
    }
    const parsed = MotivationRequest.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'bad request', detail: parsed.error.issues[0]?.message });
    }

    const day = dayKey(req.headers['x-timezone'] as string | undefined);
    const sub = await billingStore.get(req.user.id);
    const premium = isPremium(sub);

    if (config.hasDb) {
      try {
        if (!premium) {
          const used = await motivationUsageToday(req.user.id, day);
          if (used >= FREE_MOTIVATION_LIMIT) {
            // Deliberately NOT the coach's 402 code. The app falls back to its
            // written lines here and says nothing; running out of motivation is
            // not a reason to put a paywall in front of somebody.
            return res.status(429).json({ error: 'enough for today', code: 'motivation_limit' });
          }
        }
        await db.none(
          `insert into motivation_usage (user_id, day, count) values ($1, $2, 1)
           on conflict (user_id, day) do update set count = motivation_usage.count + 1`,
          [req.user.id, day],
        );
      } catch (err) {
        // Almost certainly a deploy that landed without its migration. Refuse
        // rather than carry on unmetered: an uncapped completions endpoint
        // behind a session token is a free LLM proxy, and that is a worse
        // failure than a day of written lines. 429 because the app already
        // treats it as "use the bank" and says nothing to the user.
        console.error('[motivation] meter unavailable, refusing', err);
        return res.status(429).json({ error: 'unavailable', code: 'motivation_meter' });
      }
    }

    const upstream = await fetch(GROQ_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.groqApiKey}`,
      },
      body: JSON.stringify({
        model: MOTIVATION_MODEL,
        reasoning_effort: 'low',
        messages: parsed.data.messages,
        temperature: parsed.data.temperature ?? 1.05,
        // Enough for a dozen one-line sentences and nothing else.
        max_tokens: 700,
      }),
      signal: AbortSignal.timeout(60_000),
    });

    if (!upstream.ok) {
      const detail = await upstream.text().catch(() => '');
      console.error('[motivation] upstream error', upstream.status, detail.slice(0, 300));
      return res.status(502).json({ error: 'could not write those right now' });
    }
    res.json(await upstream.json());
  } catch (err) {
    next(err);
  }
});

/**
 * Speech to text, same reasoning: the key stays here.
 *
 * Audio arrives base64 in JSON rather than multipart, matching how the avatar
 * upload already works, so the client needs no new transport.
 */
const TranscribeRequest = z.object({
  audio: z.string().max(20_000_000), // ~15MB of audio as base64
  mime: z.string().max(100).optional(),
  model: z.string().optional(),
});

/**
 * Extraction: a brain dump, or a spoken one, turned into task titles.
 *
 * Deliberately NOT metered, and that is the point of it having its own route.
 * It used to go through /coach/completions, which meant emptying your head into
 * the app spent one of the five free coaching messages a day - so the feature
 * people reach for when they are overwhelmed was rationed, and it failed with
 * "daily free message limit reached", which is a sentence about a chat quota
 * appearing on a screen that has nothing to do with chat.
 *
 * The cap exists for conversation, where each turn is a person talking to a
 * model. This is not conversation: it is one short, bounded transformation of
 * text the user has already typed or spoken, and it is the app's own plumbing.
 *
 * Unmetered is not unbounded. The client does not choose the model, the effort,
 * or the token ceiling here - the server does, so an unmetered route cannot be
 * turned into a general purpose proxy for our key - the input is capped, and
 * /api/coach already sits behind writeLimiter at 60 a minute per user.
 */
const ExtractRequest = z.object({
  // Which piece of the app's own plumbing is asking. It selects a token
  // ceiling and nothing else - the model, the effort and the temperature stay
  // the server's choice, so this cannot be widened into a general proxy by a
  // client that sends a different string.
  //
  // 'plan' exists because breaking a goal into a day-by-day plan is the same
  // kind of work as reading a brain dump - one bounded transformation of text
  // the user already typed - but its answer is a JSON array with an entry per
  // day, which does not fit in the extraction ceiling. It used to go through
  // /coach/completions, so setting a goal spent a coaching message and a
  // 30-day goal could be refused outright.
  //
  // 'feed' is the same shape again: the Feed's own instructions and today's
  // articles in, a few written-up posts out. It gets its own ceiling because
  // its answer is prose rather than a field list, and the extraction ceiling
  // truncates it mid-JSON - which reaches the phone as a feed that silently
  // never writes an edition.
  task: z.enum(['extract', 'plan', 'feed']).default('extract'),
  messages: z
    .array(
      z.object({
        role: z.enum(['system', 'user']),
        content: z.string().max(12_000),
      }),
    )
    .min(1)
    .max(4),
});

/// Room for the answer, per job. A plan is one object per day for up to a
/// couple of months; the extraction ceiling would truncate it mid-JSON, which
/// surfaces as "could not read that" rather than as a short plan.
const EXTRACT_CEILING = { extract: 1500, plan: 4000, feed: 2600 } as const;

r.post('/coach/extract', requireAuth, async (req, res, next) => {
  try {
    if (!config.groqApiKey) {
      return res.status(503).json({ error: 'coach is not configured on the server' });
    }

    const parsed = ExtractRequest.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'bad request', detail: parsed.error.issues[0]?.message });
    }

    const upstream = await fetch(GROQ_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${config.groqApiKey}`,
      },
      body: JSON.stringify({
        model: 'openai/gpt-oss-20b',
        reasoning_effort: 'low',
        messages: parsed.data.messages,
        // Low, because the answer is JSON and nothing else.
        temperature: 0.2,
        // Room for a long dump. The old path shared the summary ceiling of 300,
        // which silently truncated the JSON on a big brain dump and surfaced as
        // "failed to process" rather than as a missing task.
        max_tokens: EXTRACT_CEILING[parsed.data.task],
        stream: false,
      }),
      signal: AbortSignal.timeout(60_000),
    });

    if (!upstream.ok) {
      const detail = await upstream.text().catch(() => '');
      console.error('[coach] extract failed', upstream.status, detail.slice(0, 200));
      return res.status(502).json({ error: 'could not read that' });
    }

    res.json(await upstream.json());
  } catch (err) {
    next(err);
  }
});

r.post('/coach/transcribe', requireAuth, async (req, res, next) => {
  try {
    if (!config.groqApiKey) {
      return res.status(503).json({ error: 'coach is not configured on the server' });
    }
    const parsed = TranscribeRequest.safeParse(req.body);
    if (!parsed.success) return res.status(400).json({ error: 'bad request' });

    const form = new FormData();
    form.append(
      'file',
      new Blob([Buffer.from(parsed.data.audio, 'base64')], {
        type: parsed.data.mime ?? 'audio/m4a',
      }),
      'audio.m4a',
    );
    form.append('model', 'whisper-large-v3-turbo');

    const upstream = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.groqApiKey}` },
      body: form,
      signal: AbortSignal.timeout(60_000),
    });
    if (!upstream.ok) {
      console.error('[coach] transcribe failed', upstream.status);
      return res.status(502).json({ error: 'could not transcribe that' });
    }
    res.json(await upstream.json());
  } catch (err) {
    next(err);
  }
});

export default r;
