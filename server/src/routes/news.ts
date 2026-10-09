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
/** Entities to text. `&amp;` last, so decoding cannot invent a new entity. */
function decodeEntities(s: string): string {
  return s
    .replace(/&nbsp;/gi, ' ')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&apos;/gi, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&amp;/gi, '&');
}

/**
 * RSS text to something a person can read.
 *
 * Decode first, then strip, and do it twice. The old version stripped tags and
 * decoded entities afterwards, in that order, which is backwards for every
 * feed that matters: Google News escapes its description, so the markup
 * arrives as `&lt;a href=...&gt;` and there is nothing for the tag stripper to
 * find. Decoding then turned it into `<a href=...>` AFTER the only pass that
 * would have removed it, so the stripper did not merely miss the markup - the
 * step after it created the markup. That is what put raw anchor tags in the
 * feed.
 *
 * Twice, because feeds double-encode: `&amp;lt;a&amp;gt;` needs one pass to
 * become `&lt;a&gt;` and a second to become a tag and be removed. Two is
 * enough for everything seen in the wild and is a fixed bound rather than a
 * loop over attacker-controlled input.
 */
function plain(s: string): string {
  let out = s;
  for (let pass = 0; pass < 2; pass++) {
    out = decodeEntities(out).replace(/<[^>]*>/g, ' ');
  }
  // A lone '<' left by a truncated feed would still render as the start of a
  // tag in some clients, and it carries no meaning here either way.
  return out.replace(/[<>]/g, ' ').replace(/\s+/g, ' ').trim();
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

/** Same story from two sources is still one story. */
function dedupeKey(u: string): string {
  try {
    const x = new URL(u);
    return x.hostname.replace(/^www\./, '') + x.pathname.replace(/\/$/, '');
  } catch {
    return u;
  }
}

/** How much of a headline survives in another one. 1 means every word of it. */
function titleOverlap(a: string, b: string): number {
  const words = (t: string) =>
    new Set(
      t.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter((w) => w.length > 3),
    );
  const A = words(a);
  const B = words(b);
  if (A.size < 3) return 0;
  let n = 0;
  for (const w of A) if (B.has(w)) n++;
  return n / A.size;
}

const realUrlCache = new Map<string, { at: number; url: string | null }>();

/**
 * The real article behind a Google News headline.
 *
 * Google's links are opaque redirects: they never reach the publisher server
 * side, so they can carry no picture, and the "read the original" button on a
 * card opens a Google page rather than the reporting. Searching Bing for the
 * headline finds the same story on the publisher's own site about a third of
 * the time, which is a third of the feed's cards gaining both.
 *
 * The title gate is the whole safety of this. Bing answers almost any headline
 * with something, and without the gate it quietly returned a different article
 * on most queries - measured, 7 of 10. A real picture under somebody else's
 * headline is a worse failure than no picture, so anything below a near total
 * word match is refused.
 */
async function realArticleFor(headline: string): Promise<string | null> {
  const head = plainAttr(headline).replace(/\s+-\s+[^-]{2,40}$/, '').trim();
  if (head.length < 15) return null;

  const hit = realUrlCache.get(head);
  if (hit && Date.now() - hit.at < IMAGE_TTL_MS) return hit.url;

  let found: string | null = null;
  try {
    const res = await fetch(
      `https://www.bing.com/news/search?q=${encodeURIComponent(head)}&format=RSS`,
      {
        headers: { 'User-Agent': BROWSER_UA, Accept: 'application/rss+xml, */*' },
        signal: AbortSignal.timeout(6000),
      },
    );
    if (res.ok) {
      const xml = await res.text();
      for (const m of xml.matchAll(/<item>([\s\S]*?)<\/item>/g)) {
        const block = m[1];
        const title = tag(block, 'title');
        const link = block.match(/<link>([\s\S]*?)<\/link>/)?.[1]?.trim();
        if (!title || !link) continue;
        if (titleOverlap(head, title) < 0.8) continue;
        found = bingRealUrl(link);
        break;
      }
    }
  } catch {
    /* no better link, which is a supported state */
  }

  realUrlCache.set(head, { at: Date.now(), url: found });
  return found;
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
    // NewsAPI first when a key is configured: it returns a real image field
    // outright, so no page has to be fetched at all.
    const items: NewsItem[] = NEWS_API_KEY ? await fromNewsApi(q, limit) : [];

    if (items.length < limit) {
      // Bing and Google are asked together, and their answers are merged.
      //
      // This used to stop at the first source that returned anything, and that
      // is why the feed had no pictures. Bing is the only keyless source whose
      // links reach a publisher, so it is the only one og:image can work from,
      // but on any given query it may return two items or none. Falling
      // through on empty meant one thin moment at Bing sent the whole edition
      // to Google News, which can never carry a picture at all. Asking both
      // costs one parallel request, and a thin Bing answer gets topped up
      // instead of thrown away.
      const [bing, google] = await Promise.all([
        fromBing(q, limit).catch((e) => {
          console.warn('[news] bing failed', e);
          return [] as NewsItem[];
        }),
        fromRss(q, limit).catch((e) => {
          console.warn('[news] google failed', e);
          return [] as NewsItem[];
        }),
      ]);

      // Bing first: those are the ones that can carry a picture.
      const seen = new Set(items.map((i) => dedupeKey(i.url)));
      for (const i of [...bing, ...google]) {
        const k = dedupeKey(i.url);
        if (seen.has(k)) continue;
        seen.add(k);
        items.push(i);
        if (items.length >= limit) break;
      }
      console.log(
        `[news] "${q}": bing=${bing.length} google=${google.length} -> ${items.length}`,
      );
    }

    // Swap Google's redirects for the publisher's own page where the same
    // headline can be found on Bing. All of them, not the first six: a
    // google.com redirect can never yield a picture, because the page behind it
    // is Google's own, so every link left unresolved here is a card the feed
    // must now throw away. The work is one parallel request each and the whole
    // list is already capped by `limit`.
    const opaque = items.filter((i) => i.url.includes('news.google.com'));
    if (opaque.length > 0) {
      const real = await Promise.all(opaque.map((i) => realArticleFor(i.title)));
      opaque.forEach((item, n) => {
        const better = real[n];
        if (better) {
          item.url = better;
          item.source = item.source ?? hostOf(better);
        }
      });
      console.log(
        `[news] "${q}": resolved ${real.filter(Boolean).length} of ${opaque.length} google links`,
      );
    }

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
    console.log(
      `[news] "${q}": ${items.filter((i) => i.imageUrl).length} of ${items.length} have a picture`,
    );
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
