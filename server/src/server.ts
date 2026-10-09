import express from 'express';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { config, logMode } from './config.js';
import { db } from './db.js';
import { lookup as dnsLookupCb } from 'node:dns';
import { promisify } from 'node:util';

const dnsLookup = promisify(dnsLookupCb);
import {
  securityHeaders, cors, authLimiter, billingLimiter, writeLimiter, globalLimiter,
} from './security.js';
import { attachRealtime } from './realtime/socket.js';
import { initNotify } from './services/notify.js';
import { startDiscordPresence } from './services/discord.js';
import { startKeepAlive } from './services/keepalive.js';
import feed from './routes/feed.js';
import social from './routes/social.js';
import chat from './routes/chat.js';
import notifications from './routes/notifications.js';
import devRoutes from './routes/dev.js';
import moderationRouter from './routes/moderation.js';
import notesRouter from './routes/notes.js';
import profileRouter from './routes/profile.js';
import consentRouter from './routes/consent.js';
import accountRouter from './routes/account.js';
import coachRouter from './routes/coach.js';
import musicRouter from './routes/music.js';
import newsRouter from './routes/news.js';
import { authRouter, requireAuth } from './auth.js';
import { sessionsRouter } from './routes/sessions.js';
import { roomsRouter } from './routes/rooms.js';
import { bodyDoublingRouter } from './routes/bodydoubling.js';
import { billingRouter, billingWebhookHandler } from './routes/billing.js';

// Stamped once at import, so /version reports when this process came up. A
// redeploy of an unchanged commit still moves this, which is the only way to
// tell "deployed again" from "never deployed".
const STARTED_AT = new Date().toISOString();

const app = express();

// Behind Render's proxy. Without this express reads the proxy's address as the
// client address, so every rate limiter would share one bucket for the whole
// internet. Set to 1 rather than `true`: trusting the whole chain lets a client
// forge X-Forwarded-For and pick its own bucket.
app.set('trust proxy', 1);

app.use(securityHeaders);
app.use(cors);
app.use(globalLimiter);

// Stripe webhook needs the *raw* body to verify the signature, so it must be
// registered before the JSON body parser swallows the stream.
app.post('/api/billing/webhook', express.raw({ type: 'application/json' }), billingWebhookHandler);

// 2mb: a profile picture arrives as base64 in a JSON body (see routes/profile.ts),
// and 256kb rejected every photo a phone camera produces.
app.use(express.json({ limit: '2mb' }));

// Liveness only.
//
// This used to report which subsystems were real and which were dev fallbacks,
// which told an unauthenticated caller that Redis was in-memory and LiveKit was
// off - a map of where to push. The same detail is still available to an
// operator, just not to the internet: it goes to the startup log instead.
// Liveness, including the one dependency whose absence looks like a bug in
// the app rather than an outage.
//
// A sleeping or unreachable database fails every authenticated route and the
// sign-in button, while /health cheerfully answered {ok:true} - so "the server
// is up" and "the server can do anything" were the same answer, and telling
// them apart needed a valid Google account and a look at a log. One boolean
// is no use to an attacker (the migrations in this repo are public, the commit
// behind /version is not) and it answers in one request what otherwise costs a
// debugging round.
//
// It always answers 200: see the note on the response below.
/**
 * The shape of DATABASE_URL, with nothing identifying in it.
 *
 * Reported whenever the database is unreachable. Emits whether the username is
 * tenant-qualified, the host family and the port - never the ref, the host or
 * the password.
 */
function describeDbUrl(raw: string): string {
  try {
    const u = new URL(raw);
    const host = /pooler\.supabase\.com$/i.test(u.hostname)
      ? 'pooler'
      : /\.supabase\.(co|com)$/i.test(u.hostname)
        ? 'direct'
        : 'other';
    const qualified = u.username.includes('.');
    // The pooler host is aws-0-<region>.pooler.supabase.com. The region is not
    // a secret and it is the one field that catches a mismatch: a URL pointing
    // at the wrong region's pooler gets "tenant not found" for a project that
    // exists and is running.
    const region = u.hostname.match(/^aws-\d+-([a-z0-9-]+)\.pooler\./i)?.[1] ?? 'n/a';
    return `user=${qualified ? 'tenant-qualified' : 'plain'} host=${host} ` +
      `port=${u.port || 'default'} region=${region}`;
  } catch {
    return 'unparseable';
  }
}

/**
 * Does the project behind the username still exist?
 *
 * Supavisor answers "tenant or user not found" for a paused project, a deleted
 * one and a region mismatch alike, and those need three different actions -
 * restore it, accept the data is gone, or re-copy the connection string. Every
 * Supabase project has a DNS record at <ref>.supabase.co that survives being
 * paused and disappears when the project is deleted, so one lookup separates
 * "asleep" from "gone".
 *
 * Reports a boolean. The ref is read from the username and never emitted: it
 * identifies the project, and this response is public.
 */
async function projectRefResolves(raw: string): Promise<string> {
  try {
    const ref = new URL(raw).username.split('.')[1];
    if (!ref) return 'no-ref';
    await dnsLookup(`${ref}.supabase.co`);
    return 'yes';
  } catch (e) {
    const code = (e as { code?: string })?.code;
    return code === 'ENOTFOUND' ? 'no' : `error ${code ?? 'unknown'}`;
  }
}

app.get('/health', async (_req, res) => {
  let dbState: 'up' | 'down' | 'unconfigured' = 'unconfigured';
  let dbFault: string | null = null;
  let dbShape: string | null = null;
  let dbProject: string | null = null;
  if (config.hasDb) {
    try {
      await db.one('select 1 as ok');
      dbState = 'up';
    } catch (e) {
      console.error('[health] database unreachable:', e);
      dbState = 'down';
      // The code only, never the message: a connection failure quotes the
      // host, and the host is half the DATABASE_URL. The code is enough to
      // separate the three cases that need different fixes - ENOTFOUND or
      // ETIMEDOUT is a paused or moved database, 28P01 is a rotated password,
      // XX000 from the pooler is the tenant being unavailable.
      const err = e as { code?: string | number; name?: string; message?: string };
      dbFault = [err?.name, err?.code != null ? String(err.code) : null]
        .filter(Boolean)
        .join(' ') || 'unknown';

      // "Tenant or user not found" is Supavisor saying it cannot resolve the
      // project behind the pooler, and it has exactly two causes that need
      // opposite fixes: the project is paused, or the username in DATABASE_URL
      // is not tenant-qualified. The pooler requires `postgres.<project-ref>`;
      // the plain `postgres` that works for a direct connection is rejected
      // here, and the message is identical either way.
      //
      // The SHAPE of the URL, never the URL. Whether the username contains a
      // dot, which host family it points at and which port it uses are not
      // secrets - the password and the project ref are, and none of those
      // three carries either.
      // Unconditional, not gated on the message text. It was gated on
      // "tenant or user not found", which assumed the driver surfaces the
      // pooler's wording - it does not always, and the result was a diagnostic
      // that stayed silent during the exact outage it was written for. The
      // shape carries no secret, so there is nothing to spend by always
      // sending it when the database is down.
      dbShape = describeDbUrl(config.databaseUrl);
      dbProject = await projectRefResolves(config.databaseUrl);
    }
  }
  // Always 200, and that is deliberate. render.yaml points healthCheckPath at
  // this route, so a non-200 here does not report an outage - it causes one:
  // Render refuses to promote a deploy whose health check fails and will cycle
  // the instance that is already serving. A database that is asleep must not
  // be able to take the API down with it, least of all while somebody is
  // deploying the fix for it. The state is in the body for a human to read.
  res.json({
    ok: true,
    db: dbState,
    ...(dbFault ? { dbFault } : {}),
    ...(dbShape ? { dbShape } : {}),
    ...(dbProject ? { dbProject } : {}),
  });
});

// Which revision is actually serving.
//
// Behind auth on purpose, and the reason is the same one that stripped
// /health above: this repo is public, so publishing the exact commit to
// anonymous callers hands anyone the precise source running in production -
// a map straight to any unpatched dependency. An operator with a token can
// have it; the internet cannot.
//
// Render sets RENDER_GIT_COMMIT itself, so this cannot drift from what was
// deployed the way a hand-maintained version string does. Without it, "did
// the deploy land?" was only answerable by guessing from behaviour, and
// during the 1.0.0+5 release it was not answerable at all.
app.get('/version', requireAuth, (_req, res) => res.json({
  commit: (process.env.RENDER_GIT_COMMIT ?? 'local').slice(0, 7),
  startedAt: STARTED_AT,
}));

// Dev-only token minting, mounted before the DB guard so it always resolves.
if (!config.isProd) app.use('/api', devRoutes);

// Billing is mounted before the DB guard: the store has an in-memory fallback,
// so checkout/status work whether or not a database is attached.
app.use('/api', billingRouter);

// In dev mode (no DATABASE_URL) the persistence-backed REST routes can't serve
// real data - return a clear 503 instead of hanging on a dead DB connection.
// The realtime layer (sockets) runs fully in-memory and is unaffected.
app.use('/api', (req, res, next) => {
  if (!config.hasDb) {
    return res
      .status(503)
      .json({ error: 'DATABASE_URL not set - REST persistence is disabled in dev mode' });
  }
  next();
});

const httpServer = createServer(app);
const io = new Server(httpServer, {
  // Same allow-list as the REST layer. A native client sends no Origin, which
  // socket.io treats as same-origin and allows; a browser client must be on the
  // list. This was `'*'` by inheritance from the old CORS default.
  cors: { origin: config.clientOrigins, credentials: true },
  // Long timeouts so mobile clients survive backgrounding; the grace-period
  // eviction (presence.handleDisconnect) handles real drops.
  pingInterval: 25_000,
  pingTimeout: 20_000,
});

// REST
//
// Limiters are mounted per path group, tightest first. They sit here rather
// than inside each router so the whole policy is readable in one place.
app.use('/api/auth', authLimiter);
app.use('/api/billing', billingLimiter);
app.use(['/api/posts', '/api/conversations', '/api/comments', '/api/reports', '/api/coach'], writeLimiter);

app.use('/api', authRouter);
app.use('/api', feed);
app.use('/api', social);
app.use('/api', notesRouter);
app.use('/api', consentRouter);
app.use('/api', accountRouter);
app.use('/api', coachRouter);
app.use('/api', profileRouter);
app.use('/api', chat);
// Report and block. Mounted with the rest of the authenticated API; /api/reports
// already sits behind writeLimiter, which was configured for a route that did
// not exist yet.
app.use('/api', moderationRouter);
// Search music by name. /music/stream is deliberately open; see the route.
app.use('/api', musicRouter);
app.use('/api', newsRouter);
app.use('/api', notifications);
app.use('/api', roomsRouter(io));
app.use('/api', sessionsRouter);
app.use('/api', bodyDoublingRouter(io));

// Central error handler: routes that `next(err)` (e.g. group resolver 404s)
// land here with a clean JSON status instead of a generic 500 / hung request.
app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  const status = err?.status ?? 500;
  if (status >= 500) console.error('[api error]', err);
  res.status(status).json({ error: err?.message ?? 'internal error' });
});

// Realtime + notifications
initNotify(io);
attachRealtime(io);

httpServer.listen(config.port, () => {
  logMode();
  console.log(`OurMynd server listening on :${config.port} (${config.isProd ? 'prod' : 'dev'})`);

  // After listen, and deliberately not awaited: the Discord presence is
  // decoration, and the API must never wait on it or fail with it. It swallows
  // its own errors, so the catch here is belt and braces.
  void startDiscordPresence().catch(() => {});

  // Keeps the free instance from sleeping, which is what actually keeps the
  // bot above in the member list. See the file for why this is not free.
  startKeepAlive();
});
