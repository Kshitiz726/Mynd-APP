import express from 'express';
import cors from 'cors';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { config, logMode } from './config.js';
import { attachRealtime } from './realtime/socket.js';
import { initNotify } from './services/notify.js';
import feed from './routes/feed.js';
import social from './routes/social.js';
import chat from './routes/chat.js';
import notifications from './routes/notifications.js';
import devRoutes from './routes/dev.js';
import notesRouter from './routes/notes.js';
import { authRouter } from './auth.js';
import { sessionsRouter } from './routes/sessions.js';
import { roomsRouter } from './routes/rooms.js';
import { bodyDoublingRouter } from './routes/bodydoubling.js';
import { billingRouter, billingWebhookHandler } from './routes/billing.js';

const app = express();
app.use(cors({ origin: config.clientOrigin }));

// Stripe webhook needs the *raw* body to verify the signature, so it must be
// registered before the JSON body parser swallows the stream.
app.post('/api/billing/webhook', express.raw({ type: 'application/json' }), billingWebhookHandler);

app.use(express.json({ limit: '256kb' }));

app.get('/health', (_req, res) =>
  res.json({
    ok: true,
    mode: {
      db: config.hasDb ? 'cloud' : 'in-memory(dev)',
      redis: config.hasRedis ? 'cloud' : 'in-memory(dev)',
      livekit: config.hasLivekit ? 'on' : 'off(dev)',
    },
  }),
);

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
  cors: { origin: config.clientOrigin },
  // Long timeouts so mobile clients survive backgrounding; the grace-period
  // eviction (presence.handleDisconnect) handles real drops.
  pingInterval: 25_000,
  pingTimeout: 20_000,
});

// REST
app.use('/api', authRouter);
app.use('/api', feed);
app.use('/api', social);
app.use('/api', notesRouter);
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
