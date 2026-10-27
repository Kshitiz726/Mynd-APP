/**
 * Keeps the Render free instance awake, which is really about keeping the
 * Discord presence bot online.
 *
 * Render's free plan spins a web service down after roughly 15 minutes with no
 * INBOUND traffic. When the container stops, the bot's gateway connection dies
 * with it and OurMynd drops out of the Discord member list until the next
 * request happens to wake the service. Nothing in the bot can prevent that,
 * because the process itself is gone.
 *
 * So the service pings its own PUBLIC url on a timer. The important word is
 * public: a request to localhost never leaves the container and Render's router
 * never sees it, so it does not reset the idle timer. It has to go out to the
 * onrender.com hostname and come back in.
 *
 * This is a workaround, not a fix. The real fix is a paid instance. It also
 * spends free instance hours, which are finite - see the note in render.yaml.
 */
import { config } from '../config.js';

/** Comfortably inside Render's ~15 minute idle window, with room for a miss. */
const PING_INTERVAL_MS = 10 * 60 * 1000;

/**
 * Where to ping. RENDER_EXTERNAL_URL is injected by Render itself for web
 * services, so it needs no configuration and is always correct, even if the
 * service is renamed. PUBLIC_BASE_URL is the manual fallback the billing and
 * music routes already use.
 */
function publicUrl(): string | null {
  const raw = process.env.RENDER_EXTERNAL_URL || process.env.PUBLIC_BASE_URL || '';
  if (!raw) return null;
  // A localhost value is a dev config, and pinging it would do nothing useful
  // while still firing a request every ten minutes forever.
  if (/^https?:\/\/(localhost|127\.0\.0\.1)/i.test(raw)) return null;
  return raw.replace(/\/+$/, '');
}

export function startKeepAlive(): void {
  // Only in production, and only when there is a real public hostname to hit.
  if (!config.isProd) return;

  // A standby server must not keep itself awake.
  //
  // Redundancy on a free plan only works if the spares cost nothing while they
  // are spare: Render stops charging instance hours the moment a service idles
  // out, and wakes it again on the next request. This ping would prevent that
  // for ever, so a backup with it left on burns a full month of hours serving
  // nobody - which is the exact failure that took the first account down.
  // Set KEEPALIVE=off on every server except the one currently in service.
  if ((process.env.KEEPALIVE ?? '').trim().toLowerCase() === 'off') {
    console.log('[keepalive] off: standby server, letting Render idle it out');
    return;
  }

  const base = publicUrl();
  if (!base) {
    console.log('[keepalive] no public URL, not pinging');
    return;
  }

  const target = `${base}/health`;
  console.log(`[keepalive] pinging ${target} every ${PING_INTERVAL_MS / 60000} min`);

  const tick = async () => {
    try {
      // An abort guard, so a hung request cannot stack up sockets over days.
      const res = await fetch(target, {
        signal: AbortSignal.timeout(15_000),
        headers: { 'user-agent': 'ourmynd-keepalive' },
      });
      // Deliberately quiet on success. This fires 144 times a day and logging
      // each one would bury everything worth reading in the Render logs.
      if (!res.ok) console.warn(`[keepalive] ping returned ${res.status}`);
    } catch (err) {
      console.warn('[keepalive] ping failed:', (err as Error)?.message ?? err);
    }
  };

  // One ping straight away, so a misconfigured URL shows up in the deploy
  // logs immediately rather than ten minutes later when nobody is watching.
  void tick();

  // unref so the timer never holds the process open on shutdown.
  setInterval(tick, PING_INTERVAL_MS).unref();
}
