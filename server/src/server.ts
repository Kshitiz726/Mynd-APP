import express from 'express';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { config, logMode } from './config.js';
import {
  securityHeaders, cors, authLimiter, billingLimiter, writeLimiter, globalLimiter,
} from './security.js';
import { attachRealtime } from './realtime/socket.js';
import { initNotify } from './services/notify.js';
import feed from './routes/feed.js';
import social from './routes/social.js';
import chat from './routes/chat.js';
import notifications from './routes/notifications.js';
import devRoutes from './routes/dev.js';
import notesRouter from './routes/notes.js';
import profileRouter from './routes/profile.js';
import consentRouter from './routes/consent.js';
import accountRouter from './routes/account.js';
import coachRouter from './routes/coach.js';
import { authRouter } from './auth.js';
import { sessionsRouter } from './routes/sessions.js';
import { roomsRouter } from './routes/rooms.js';
import { bodyDoublingRouter } from './routes/bodydoubling.js';
import { billingRouter, billingWebhookHandler } from './routes/billing.js';

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
app.get('/health', (_req, res) => res.json({ ok: true }));

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
});
