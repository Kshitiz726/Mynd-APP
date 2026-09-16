import { Router } from 'express';

import { requireAuth } from '../auth.js';

/**
 * Search music by name, and hand back something the room can actually play.
 *
 * Until now the only way to put music on was to paste a link, which means
 * leaving the app, finding the track, copying the URL and coming back - four
 * steps, during a feature whose entire purpose is not losing your thread. You
 * type a name here and the best match plays.
 *
 * Audius is the source: a public API with no key, no quota and full length
 * tracks, where the catalogue is overwhelmingly the instrumental and
 * electronic music people actually put on to concentrate. A mainstream vocal
 * track by name will miss, and that is the accepted trade.
 *
 * The stream URL we hand out is our own, not Audius's, for two reasons that
 * both matter. Audius signs its stream URLs with a timestamp, so the real one
 * expires and would die in a room halfway through a session. And the client
 * and server both refuse a stream URL whose last path segment has no audio
 * extension, which is a deliberate guard against broadcasting a web page to a
 * room - Audius's endpoint ends in `/stream`. Ours ends in `.mp3`, never
 * expires, and is identical for everyone in the room.
 *
 * It is a redirect, not a proxy. The bytes go straight from Audius to the
 * device, so this costs the server one small request per play rather than the
 * bandwidth of every session in the app.
 */
const r = Router();

const APP_NAME = 'OurMynd';

/** Audius ids are short base-36-ish strings. Pinned so `id` cannot walk paths. */
const AUDIUS_ID = /^[A-Za-z0-9]{1,16}$/;

/**
 * Audius has no single hostname: you ask for a discovery node and use what you
 * are given. Cached for an hour so a room full of people changing tracks does
 * not re-resolve it every time, and re-resolved on failure rather than pinned,
 * because the node that answered an hour ago may be gone.
 */
let host: { url: string; at: number } | null = null;
const HOST_TTL_MS = 60 * 60 * 1000;

async function discoveryHost(force = false): Promise<string> {
  if (!force && host && Date.now() - host.at < HOST_TTL_MS) return host.url;
  const res = await fetch('https://api.audius.co', { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`audius discovery failed: ${res.status}`);
  const body = (await res.json()) as { data?: string[] };
  const url = body.data?.[0];
  if (!url) throw new Error('audius returned no hosts');
  host = { url, at: Date.now() };
  return url;
}

interface AudiusTrack {
  id: string;
  title: string;
  duration?: number;
  user?: { name?: string };
  artwork?: Record<string, string>;
}

function selfBase(req: { protocol: string; get(h: string): string | undefined }): string {
  const configured = process.env.PUBLIC_BASE_URL;
  if (configured) return configured.replace(/\/+$/, '');
  return `${req.protocol}://${req.get('host')}`;
}

// ── Search ──
r.get('/music/search', requireAuth, async (req, res, next) => {
  try {
    const q = String(req.query.q ?? '').trim();
    if (q.length < 2) return res.status(400).json({ error: 'query too short' });
    if (q.length > 120) return res.status(400).json({ error: 'query too long' });

    const search = async (h: string) =>
      fetch(
        `${h}/v1/tracks/search?query=${encodeURIComponent(q)}&app_name=${APP_NAME}`,
        { signal: AbortSignal.timeout(10_000) },
      );

    let upstream = await search(await discoveryHost());
    // A dead node looks exactly like a bad query from here, so re-resolve once
    // before deciding the search failed.
    if (!upstream.ok) upstream = await search(await discoveryHost(true));
    if (!upstream.ok) return res.status(502).json({ error: 'search unavailable' });

    const data = ((await upstream.json()) as { data?: AudiusTrack[] }).data ?? [];
    const base = selfBase(req);
    const results = data
      .filter((t) => t && AUDIUS_ID.test(t.id) && t.title)
      .slice(0, 8)
      .map((t) => ({
        id: t.id,
        title: t.title,
        artist: t.user?.name ?? '',
        durationSecs: t.duration ?? null,
        artworkUrl: t.artwork?.['480x480'] ?? t.artwork?.['150x150'] ?? null,
        // What the client sets as the room's music. Ends in .mp3 on purpose.
        url: `${base}/api/music/stream/${t.id}.mp3`,
      }));

    res.json({ results });
  } catch (err) {
    next(err);
  }
});

// ── Stream ──
//
// Deliberately unauthenticated. The audio player fetches this URL itself and
// sends none of our headers, so requiring a session here would mean nothing
// ever played. It is safe to leave open because it only ever redirects to
// Audius for an id that matches the pattern above, and Audius track ids are
// public. Nothing about the caller is read, and no bytes pass through us.
r.get('/music/stream/:file', async (req, res, next) => {
  try {
    const file = String(req.params.file ?? '');
    const id = file.endsWith('.mp3') ? file.slice(0, -4) : file;
    if (!AUDIUS_ID.test(id)) return res.status(400).json({ error: 'bad id' });

    const h = await discoveryHost();
    res.redirect(302, `${h}/v1/tracks/${id}/stream?app_name=${APP_NAME}`);
  } catch (err) {
    next(err);
  }
});

export default r;
