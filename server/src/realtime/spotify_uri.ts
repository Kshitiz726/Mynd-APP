/**
 * Canonicalise whatever a human pasted into a Spotify URI.
 *
 * This exists on the server as well as the client because the client's answer
 * is not trustworthy: `set_music` is broadcast to every participant, so an
 * unvalidated string is a way to push arbitrary text - or a link to somewhere
 * else entirely - onto other people's screens.
 *
 * All of these are the same playlist and must normalise identically:
 *   https://open.spotify.com/playlist/{id}
 *   https://open.spotify.com/playlist/{id}?si=...        share link
 *   https://open.spotify.com/intl-de/playlist/{id}       locale-prefixed
 *   http://open.spotify.com/playlist/{id}                no TLS
 *   spotify:playlist:{id}                                already canonical
 */

/** The resource kinds worth accepting. Anything else is rejected. */
const KINDS = ['track', 'album', 'playlist', 'artist', 'show', 'episode'] as const;
type Kind = (typeof KINDS)[number];

/**
 * Spotify ids are base62, 22 characters in practice. The length is not pinned
 * to 22 because that is an observation rather than a documented guarantee, but
 * it is bounded so a pasted essay cannot become an id.
 */
const ID = /^[A-Za-z0-9]{16,40}$/;

/** Hard ceiling before any parsing, so a megabyte of text is cheap to reject. */
const MAX_INPUT = 400;

export function normaliseSpotifyUri(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  const raw = input.trim();
  if (raw.length === 0 || raw.length > MAX_INPUT) return null;

  // Already a URI.
  const uri = raw.match(/^spotify:([a-z]+):([A-Za-z0-9]+)$/);
  if (uri) {
    const [, kind, id] = uri;
    return isKind(kind) && ID.test(id) ? `spotify:${kind}:${id}` : null;
  }

  // A web URL. Parsed with URL rather than a regex so that credentials, ports
  // and odd escaping are handled by something that already knows the rules.
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  if (url.hostname !== 'open.spotify.com' && url.hostname !== 'play.spotify.com') {
    return null;
  }

  // Drop a leading locale segment: /intl-de/playlist/{id}.
  const parts = url.pathname.split('/').filter(Boolean);
  if (parts[0]?.startsWith('intl-')) parts.shift();
  if (parts.length < 2) return null;

  const [kind, id] = parts;
  // The query string is discarded on purpose. `?si=` is a share token that
  // identifies the person who sent the link, and storing it would leak that
  // into every participant's client for no benefit.
  return isKind(kind) && ID.test(id) ? `spotify:${kind}:${id}` : null;
}

function isKind(v: string): v is Kind {
  return (KINDS as readonly string[]).includes(v);
}
