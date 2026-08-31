/**
 * Canonicalise whatever a human pasted into a music link we can act on.
 *
 * This exists on the server as well as the client (lib/core/utils/music_link.dart)
 * because the client's answer is not trustworthy: `set_music` is broadcast to
 * every participant, so an unvalidated string is a way to push arbitrary text -
 * or a link to somewhere else entirely - onto other people's screens.
 *
 * The canonical form is `{provider}:{kind}:{id}` for both providers, so
 * everything downstream stores and compares one shape of string.
 *
 * All of these are the same playlist and must normalise identically:
 *   https://open.spotify.com/playlist/{id}
 *   https://open.spotify.com/playlist/{id}?si=...        share link
 *   https://open.spotify.com/intl-de/playlist/{id}       locale-prefixed
 *   spotify:playlist:{id}                                already canonical
 *
 * And all of these are the same video:
 *   https://www.youtube.com/watch?v={id}
 *   https://youtu.be/{id}?si=...                         share link
 *   https://m.youtube.com/watch?v={id}&t=42
 *   https://music.youtube.com/watch?v={id}
 */

export type MusicProvider = 'spotify' | 'youtube' | 'stream';

export type MusicLink = {
  provider: MusicProvider;
  kind: string;
  id: string;
  /** `{provider}:{kind}:{id}` */
  uri: string;
};

const SPOTIFY_KINDS = ['track', 'album', 'playlist', 'artist', 'show', 'episode'] as const;

/**
 * Spotify ids are base62, 22 characters in practice. The length is not pinned
 * to 22 because that is an observation rather than a documented guarantee, but
 * it is bounded so a pasted essay cannot become an id.
 */
const SPOTIFY_ID = /^[A-Za-z0-9]{16,40}$/;

/** YouTube video ids ARE documented as 11 URL-safe characters, so pin it. */
const YT_VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const YT_PLAYLIST_ID = /^[A-Za-z0-9_-]{12,42}$/;

/**
 * Audio containers and manifests worth accepting as a direct stream.
 *
 * An extension is required rather than accepting any URL: without one there is
 * no way to tell an audio endpoint from an HTML page, and broadcasting a web
 * page to a room produces a silent failure that looks like a bug.
 */
const AUDIO_EXT = new Set([
  'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'flac', 'wav', 'weba',
  'm3u8', 'pls',
]);

function streamFromUrl(url: URL): MusicLink | null {
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;
  if (!url.hostname) return null;
  const segs = url.pathname.split('/').filter(Boolean);
  if (segs.length === 0) return null;
  const last = segs[segs.length - 1].toLowerCase();
  const dot = last.lastIndexOf('.');
  if (dot < 0) return null;
  if (!AUDIO_EXT.has(last.slice(dot + 1))) return null;
  // The query is kept: stream endpoints routinely carry a required token or
  // bitrate selector, and dropping it would break the URL.
  const id = Buffer.from(url.toString(), 'utf8').toString('base64url');
  return { provider: 'stream', kind: 'audio', id, uri: `stream:audio:${id}` };
}

function streamFromId(kind: string, id: string): MusicLink | null {
  if (kind !== 'audio') return null;
  try {
    const url = new URL(Buffer.from(id, 'base64url').toString('utf8'));
    return streamFromUrl(url);
  } catch {
    return null;
  }
}

const SPOTIFY_HOSTS = new Set(['open.spotify.com', 'play.spotify.com']);
const YOUTUBE_HOSTS = new Set([
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
]);
const YOUTUBE_SHORT_HOSTS = new Set(['youtu.be', 'www.youtu.be']);

/** Hard ceiling before any parsing, so a megabyte of text is cheap to reject. */
const MAX_INPUT = 400;

function spotify(kind: string, id: string): MusicLink | null {
  if (!(SPOTIFY_KINDS as readonly string[]).includes(kind)) return null;
  if (!SPOTIFY_ID.test(id)) return null;
  return { provider: 'spotify', kind, id, uri: `spotify:${kind}:${id}` };
}

function youtube(kind: string, id: string | null | undefined): MusicLink | null {
  if (!id) return null;
  if (kind === 'video' && YT_VIDEO_ID.test(id)) {
    return { provider: 'youtube', kind, id, uri: `youtube:video:${id}` };
  }
  if (kind === 'playlist' && YT_PLAYLIST_ID.test(id)) {
    return { provider: 'youtube', kind, id, uri: `youtube:playlist:${id}` };
  }
  return null;
}

/** Rebuild from a canonical string, or null if it is not one. */
export function parseCanonical(canonical: unknown): MusicLink | null {
  if (typeof canonical !== 'string') return null;
  const parts = canonical.split(':');
  if (parts.length !== 3) return null;
  const [provider, kind, id] = parts;
  if (provider === 'spotify') return spotify(kind, id);
  if (provider === 'youtube') return youtube(kind, id);
  if (provider === 'stream') return streamFromId(kind, id);
  return null;
}

export function parseMusicLink(input: unknown): MusicLink | null {
  if (typeof input !== 'string') return null;
  const raw = input.trim();
  if (raw.length === 0 || raw.length > MAX_INPUT) return null;

  // Already canonical, or a spotify: URI.
  const direct = parseCanonical(raw);
  if (direct) return direct;

  const uri = raw.match(/^spotify:([a-z]+):([A-Za-z0-9]+)$/);
  if (uri) return spotify(uri[1], uri[2]);

  // Parsed with URL rather than a regex so that credentials, ports and odd
  // escaping are handled by something that already knows the rules.
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null;

  const host = url.hostname.toLowerCase();
  if (SPOTIFY_HOSTS.has(host)) return fromSpotifyUrl(url);
  if (YOUTUBE_HOSTS.has(host)) return fromYoutubeUrl(url);
  if (YOUTUBE_SHORT_HOSTS.has(host)) {
    const parts = url.pathname.split('/').filter(Boolean);
    // youtu.be/{id}. The `?si=` share token and `?t=` are dropped with the query.
    return parts.length === 1 ? youtube('video', parts[0]) : null;
  }
  // Anything else is only interesting if it points straight at audio.
  return streamFromUrl(url);
}

function fromSpotifyUrl(url: URL): MusicLink | null {
  const parts = url.pathname.split('/').filter(Boolean);
  // Drop a leading locale segment: /intl-de/playlist/{id}.
  if (parts[0]?.startsWith('intl-')) parts.shift();
  if (parts.length < 2) return null;
  // The query string is discarded on purpose. `?si=` is a share token that
  // identifies the person who sent the link, and storing it would leak that
  // into every participant's client for no benefit.
  return spotify(parts[0], parts[1]);
}

function fromYoutubeUrl(url: URL): MusicLink | null {
  const parts = url.pathname.split('/').filter(Boolean);
  const v = url.searchParams.get('v');
  const list = url.searchParams.get('list');

  // A watch URL can also carry ?list=, but the video is what the sender was
  // looking at, so it wins.
  if (parts[0] === 'watch' && v) return youtube('video', v);
  if (parts[0] === 'playlist' && list) return youtube('playlist', list);
  if (parts.length >= 2 && ['shorts', 'embed', 'live', 'v'].includes(parts[0])) {
    return youtube('video', parts[1]);
  }
  if (v) return youtube('video', v);
  if (list) return youtube('playlist', list);
  return null;
}

/** The canonical string, or null. Convenience for callers that only store it. */
export function normaliseMusicUri(input: unknown): string | null {
  return parseMusicLink(input)?.uri ?? null;
}
