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

/** Where the list of servers lives. Overridable so a smoke test can serve it. */
function serverFileUrl(): string {
  return process.env.SERVER_FILE_URL || 'https://www.ourmynd.com/servers.json';
}

/** Bare origin, lowercased, no trailing slash - so two spellings of the same
 * server compare equal. Returns null for anything that is not a URL. */
export function origin(raw: unknown): string | null {
  if (typeof raw !== 'string' || !raw.trim()) return null;
  try {
    const u = new URL(raw.trim());
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return null;
    return `${u.protocol}//${u.host.toLowerCase()}`;
  } catch {
    return null;
  }
}

/** The servers the file names, in priority order: `api` first, then `servers`. */
export function listedServers(body: unknown): string[] {
  const out: string[] = [];
  const add = (raw: unknown) => {
    const o = origin(raw);
    if (o && !out.includes(o)) out.push(o);
  };
  if (body && typeof body === 'object') {
    const b = body as Record<string, unknown>;
    add(b.api);
    if (Array.isArray(b.servers)) for (const e of b.servers) add(e);
  }
  return out;
}

/**
 * Where this server sits in the running order. -1 when it is not listed.
 *
 * Pure, so the ranking rule can be exercised without a network.
 */
export function rankOf(listed: string[], self: string): number {
  const me = origin(self);
  return me ? listed.indexOf(me) : -1;
}

/** Is this server reachable and serving? */
async function answers(base: string): Promise<boolean> {
  try {
    const res = await fetch(`${base}/health`, {
      signal: AbortSignal.timeout(20_000),
      headers: { 'user-agent': 'ourmynd-keepalive-probe' },
    });
    if (!res.ok) return false;
    const body = (await res.json()) as { ok?: unknown };
    return body?.ok === true;
  } catch {
    return false;
  }
}

/**
 * Should this server be keeping itself awake right now?
 *
 * Priority election over the shared list, the way VRRP picks a master: the
 * highest-ranked server that is actually up is the one in service, everyone
 * below it stands down and lets Render idle them out. No handover message is
 * sent and no token exists - each server works it out for itself - so the one
 * guarantee this cannot make is strict mutual exclusion. A blip that hides the
 * primary makes a standby think it is in charge, both stay awake, and the next
 * tick puts it right. Minutes of overlap, bought in exchange for needing no
 * coordination at all.
 *
 * **Every uncertain answer is "stay awake".** Wrongly staying up costs instance
 * hours; wrongly standing down takes the live server cold and the users with
 * it. So an unreadable file, an unparseable file, or a server that cannot find
 * itself in the list all keep pinging.
 */
async function inService(self: string): Promise<boolean> {
  let listed: string[];
  try {
    const res = await fetch(serverFileUrl(), {
      signal: AbortSignal.timeout(10_000),
      headers: { 'user-agent': 'ourmynd-keepalive', 'cache-control': 'no-cache' },
    });
    if (!res.ok) {
      console.warn(`[keepalive] server list returned ${res.status}, staying awake`);
      return true;
    }
    listed = listedServers(await res.json());
  } catch (err) {
    console.warn('[keepalive] could not read the server list, staying awake:',
      (err as Error)?.message ?? err);
    return true;
  }

  const rank = rankOf(listed, self);
  if (rank < 0) {
    // Not in the file at all. No app will ever be sent here, so this is almost
    // certainly a misconfiguration - and the safe reading of a misconfiguration
    // is not to put the server to sleep.
    console.warn(`[keepalive] ${self} is not in the server list, staying awake`);
    return true;
  }
  if (rank === 0) return true;

  // Only stand down on positive evidence that somebody better is serving.
  for (const better of listed.slice(0, rank)) {
    if (await answers(better)) {
      console.log(`[keepalive] standing down, ${better} is serving`);
      return false;
    }
  }
  console.log(`[keepalive] every server above us is down, taking over`);
  return true;
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
  // KEEPALIVE=off pins a server down whatever the election says; KEEPALIVE=always
  // pins it up. Unset is the normal case and means "work it out from the list".
  const mode = (process.env.KEEPALIVE ?? '').trim().toLowerCase();
  if (mode === 'off') {
    console.log('[keepalive] off: standby server, letting Render idle it out');
    return;
  }
  const elect = mode !== 'always' && mode !== 'on';

  const base = publicUrl();
  if (!base) {
    console.log('[keepalive] no public URL, not pinging');
    return;
  }

  const target = `${base}/health`;
  console.log(`[keepalive] ${elect ? 'electing' : 'always on'}: ${target} every `
    + `${PING_INTERVAL_MS / 60000} min`);

  const tick = async () => {
    // Asked every tick rather than once at boot, because which server is in
    // service is exactly the thing that changes while this process is alive.
    // Standing down only skips the ping: the timer stays armed so this server
    // can take over later, and with nothing to keep it warm Render idles it out
    // on its own.
    if (elect && !(await inService(base))) return;
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
