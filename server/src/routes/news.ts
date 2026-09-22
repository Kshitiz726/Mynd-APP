import { Router } from 'express';

import { requireAuth } from '../auth.js';

/**
 * The Feed's news, fetched server side rather than on the phone.
 *
 * Two sources, in order of preference:
 *
 *   NewsAPI, when NEWS_API_KEY is set. Real editorial metadata: a summary, a
 *   source name, and an article image, which is what the Feed's card layout
 *   actually needs.
 *
 *   Google News RSS otherwise. No key, no quota, works today. It carries a
 *   title, a link, a source and a date, but no image and only a scrap of
 *   description, so cards fall back to a text-only treatment.
 *
 * Server side for three reasons. A NewsAPI key in the binary is a key anybody
 * can pull out of it. NewsAPI's developer plan refuses browser and mobile
 * origins outright, so the phone cannot call it even with a key. And parsing
 * somebody's RSS is the kind of thing that breaks quietly, which is easier to
 * fix in one deploy than in a release cycle.
 *
 * Only headlines, summaries and the publisher's own image are used, each
 * linked back to the source. The body of a story is the publisher's
 * copyrighted reporting and is never reproduced.
 */
const r = Router();

const NEWS_API_KEY = process.env.NEWS_API_KEY;

/** One shared cache. News is the same for everyone in a place. */
type Cached = { at: number; items: NewsItem[] };
const cache = new Map<string, Cached>();
const TTL_MS = 10 * 60 * 1000;

export type NewsItem = {
  title: string;
  summary: string | null;
  url: string;
  imageUrl: string | null;
  source: string | null;
  publishedAt: string | null;
};

const BROWSER_UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/**
 * The publisher's own share image, read off the article page.
 *
 * Google News RSS carries no images whatsoever - no media:content, no
 * thumbnail, no enclosure, not even an img tag in the description - so a feed
 * built on it is text-only no matter how the cards are written. The picture has
 * to come from the article itself.
 *
 * og:image is the right thing to take: it is the image the publisher chose for
 * exactly this purpose, it is meant to be hotlinked, and reading one meta tag
 * is not scraping their reporting.
 *
 * Bounded hard, because this runs per article: one request, four seconds, only
 * the first 60KB of the page (og:image lives in the head), and any failure at
 * all resolves to null. A missing picture costs a picture.
 */
const imageCache = new Map<string, { at: number; url: string | null }>();
const IMAGE_TTL_MS = 6 * 60 * 60 * 1000;

async function ogImage(articleUrl: string): Promise<string | null> {
  // Google News links are opaque redirects that never reach the publisher
  // server side: the page they serve is Google's own, and its og:image is the
  // same grey Google News card for every article in the feed. Measured, not
  // assumed - four different stories returned one identical URL. Asking is a
  // wasted round trip per item, so they are skipped and those cards are
  // text-only until a keyed source is configured.
  if (articleUrl.includes('news.google.com')) return null;

  const hit = imageCache.get(articleUrl);
  if (hit && Date.now() - hit.at < IMAGE_TTL_MS) return hit.url;

  let found: string | null = null;
  try {
    const res = await fetch(articleUrl, {
      headers: { 'User-Agent': BROWSER_UA, Accept: 'text/html' },
      signal: AbortSignal.timeout(4000),
      redirect: 'follow',
    });
    if (res.ok) {
      // The head is all that matters, and some articles are megabytes.
      const reader = res.body?.getReader();
      let html = '';
      if (reader) {
        const dec = new TextDecoder();
        while (html.length < 60_000) {
          const { done, value } = await reader.read();
          if (done) break;
          html += dec.decode(value, { stream: true });
        }
        await reader.cancel().catch(() => {});
      }
      const m =
        html.match(
          /<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i,
        ) ??
        html.match(
          /<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i,
        ) ??
        html.match(
          /<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i,
        );
      const raw = m?.[1]?.trim();
      // Only absolute https. A relative path would need the resolved article
      // host, and an http image is blocked by App Transport Security anyway.
      if (raw && raw.startsWith('https://')) found = raw;
    }
  } catch {
    /* no picture, which is a supported state */
  }

  imageCache.set(articleUrl, { at: Date.now(), url: found });
  return found;
}

/** Strip tags and decode the handful of entities RSS actually emits. */
function plain(s: string): string {
  return s
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, d) => String.fromCharCode(Number(d)))
    .replace(/\s+/g, ' ')
    .trim();
}

function tag(block: string, name: string): string | null {
  const m = block.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, 'i'));
  if (!m) return null;
  const raw = m[1].replace(/^<!\[CDATA\[([\s\S]*?)\]\]>$/, '$1');
  const out = plain(raw);
  return out || null;
}

async function fromRss(query: string, limit: number): Promise<NewsItem[]> {
  const q = encodeURIComponent(query);
  const url = `https://news.google.com/rss/search?q=${q}&hl=en&gl=US&ceid=US:en`;
  // A browser-shaped User-Agent. Google answers a datacenter IP carrying an
  // obviously-a-bot agent with a consent interstitial or a 429, and the body
  // that comes back is HTML rather than RSS - which parses to zero items and
  // looks exactly like a quiet news day.
  const res = await fetch(url, {
    headers: {
      'User-Agent': BROWSER_UA,
      Accept: 'application/rss+xml, application/xml;q=0.9, */*;q=0.8',
    },
  });
  if (!res.ok) {
    console.warn(`[news] rss for "${query}" -> HTTP ${res.status}`);
    return [];
  }
  const xml = await res.text();
  if (!xml.includes('<item>')) {
    // Reached Google and got something that is not a feed.
    console.warn(
      `[news] rss for "${query}" -> ${xml.length} bytes with no <item>`,
    );
    return [];
  }

  const items: NewsItem[] = [];
  for (const m of xml.matchAll(/<item>([\s\S]*?)<\/item>/g)) {
    const block = m[1];
    const title = tag(block, 'title');
    if (!title) continue;
    // Google wraps the publisher name into the title after a trailing dash.
    const dash = title.lastIndexOf(' - ');
    const source = tag(block, 'source') ?? (dash > 0 ? title.slice(dash + 3) : null);
    items.push({
      title: dash > 0 ? title.slice(0, dash) : title,
      summary: tag(block, 'description'),
      url: tag(block, 'link') ?? '',
      imageUrl: null,
      source,
      publishedAt: tag(block, 'pubDate'),
    });
    if (items.length >= limit) break;
  }
  return items;
}

/**
 * Bing News, which is searchable, needs no key, and - the part that matters -
 * hands back the publisher's real URL.
 *
 * Google News was the original source and cannot carry a picture by any route:
 * its RSS has no image fields at all, and its links are opaque redirects whose
 * pages are Google's own, so og:image there returns the same grey card for
 * every story. Measured, not assumed.
 *
 * Bing wraps the link in an apiclick tracker, but the real article sits in the
 * `url=` query parameter in plain URL-encoded form. Pulling it out gives a
 * genuine publisher page, which means og:image finds a genuine article image.
 * Six out of six on the first live sample, in about a second and a half.
 */
function bingRealUrl(link: string): string | null {
  const m = plainAttr(link).match(/[?&]url=([^&]+)/);
  if (m) {
    try {
      return decodeURIComponent(m[1]);
    } catch {
      return null;
    }
  }
  // Anything that is still a Bing URL is a tracker we could not unwrap, and
  // is no use to us: it neither renders nor resolves to an image.
  return link.includes('bing.com') ? null : link;
}

/** Entity-decode without stripping tags, which `plain` would do to a URL. */
function plainAttr(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

async function fromBing(query: string, limit: number): Promise<NewsItem[]> {
  const q = encodeURIComponent(query);
  const url = `https://www.bing.com/news/search?q=${q}&format=RSS`;
  const res = await fetch(url, {
    headers: { 'User-Agent': BROWSER_UA, Accept: 'application/rss+xml, */*' },
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) {
    console.warn(`[news] bing for "${query}" -> HTTP ${res.status}`);
    return [];
  }
  const xml = await res.text();

  const items: NewsItem[] = [];
  for (const m of xml.matchAll(/<item>([\s\S]*?)<\/item>/g)) {
    const block = m[1];
    const title = tag(block, 'title');
    const rawLink = block.match(/<link>([\s\S]*?)<\/link>/)?.[1]?.trim();
    if (!title || !rawLink) continue;
    const real = bingRealUrl(rawLink);
    if (!real) continue;
    items.push({
      title,
      summary: tag(block, 'description'),
      url: real,
      imageUrl: null,
      // Bing does not name the publisher, but the URL does, and a domain is
      // more honest than a guess.
      source: hostOf(real),
      publishedAt: tag(block, 'pubDate'),
    });
    if (items.length >= limit) break;
  }
  return items;
}

function hostOf(u: string): string | null {
  try {
    return new URL(u).hostname.replace(/^www\./, '');
  } catch {
    return null;
  }
}

async function fromNewsApi(query: string, limit: number): Promise<NewsItem[]> {
  const q = encodeURIComponent(query);
  const url =
    `https://newsapi.org/v2/everything?q=${q}&language=en&sortBy=publishedAt&pageSize=${limit}`;
  const res = await fetch(url, { headers: { 'X-Api-Key': NEWS_API_KEY as string } });
  if (!res.ok) return [];
  const j = (await res.json()) as {
    articles?: Array<{
      title?: string;
      description?: string;
      url?: string;
      urlToImage?: string;
      publishedAt?: string;
      source?: { name?: string };
    }>;
  };
  return (j.articles ?? [])
    .filter((a) => a.title && a.url && a.title !== '[Removed]')
    .map((a) => ({
      title: a.title as string,
      summary: a.description ?? null,
      url: a.url as string,
      imageUrl: a.urlToImage ?? null,
      source: a.source?.name ?? null,
      publishedAt: a.publishedAt ?? null,
    }));
}

/**
 * GET /api/news?q=<topic or place>&limit=<n>
 *
 * Never throws at the caller. The Feed is glanceable content, so a source
 * having a bad day degrades to fewer cards, never an error screen.
 */
r.get('/news', requireAuth, async (req, res) => {
  const q = String(req.query.q ?? '').trim() || 'world';
  const limit = Math.min(Math.max(Number(req.query.limit ?? 12) || 12, 1), 30);
  const key = `${q}::${limit}`;

  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < TTL_MS) {
    return res.json({ items: hit.items, cached: true });
  }

  try {
    // Three sources, in descending order of what they can give a card.
    //
    // NewsAPI first when a key is configured: it returns a real image field
    // outright, so no page has to be fetched at all.
    //
    // Bing second, and it is the one that makes a keyless feed look like
    // anything: real publisher URLs, so og:image can find real pictures.
    //
    // Google News last, as the thing that always answers. It can never carry
    // a picture, so those editions are text-only - better than empty.
    let items = NEWS_API_KEY ? await fromNewsApi(q, limit) : [];
    if (items.length === 0) {
      try {
        items = await fromBing(q, limit);
      } catch (e) {
        console.warn('[news] bing failed', e);
      }
    }
    if (items.length === 0) items = await fromRss(q, limit);

    // Pictures, in parallel, for whatever has none. Parallel because this is
    // the slow part and doing it in series would put ten seconds on a feed
    // somebody is waiting for; Promise.all is safe because ogImage never
    // rejects.
    const missing = items.filter((i) => !i.imageUrl && i.url);
    if (missing.length > 0) {
      const found = await Promise.all(missing.map((i) => ogImage(i.url)));
      missing.forEach((item, n) => {
        item.imageUrl = found[n];
      });
    }
    // Only cache a real answer. Caching an empty list pins the failure in
    // place for ten minutes, so one bad moment upstream becomes an empty feed
    // for everybody until the TTL expires.
    if (items.length > 0) cache.set(key, { at: Date.now(), items });
    res.json({
      items,
      cached: false,
      // Said out loud so the client can tell "nothing today" from "the source
      // would not talk to us". An empty feed with no explanation cost a whole
      // afternoon of guessing once already.
      ...(items.length === 0
        ? { reason: 'the news source returned nothing for that query' }
        : {}),
    });
  } catch (e) {
    console.error('[news] failed', e);
    // Serve something stale rather than nothing.
    res.json({
      items: hit?.items ?? [],
      items_stale: Boolean(hit),
      cached: false,
      reason: 'could not reach the news source',
    });
  }
});

export default r;
