import type { Request, Response, NextFunction, RequestHandler } from 'express';
import helmet from 'helmet';
import rateLimit, { ipKeyGenerator } from 'express-rate-limit';
import { config } from './config.js';

/**
 * Transport and abuse hardening, in one place so it is auditable in one read.
 *
 * None of this existed before: no security headers, no throttling, and a
 * wildcard CORS policy in production. Each export below closes one of those.
 */

/**
 * Security headers.
 *
 * HSTS is the one that matters most here - TLS terminates at the platform edge
 * and nothing told a browser to refuse plaintext next time, so a first-visit
 * downgrade was never prevented. Two years, subdomains included, preload-ready.
 *
 * The CSP is deliberately tight because this server returns JSON to a native
 * app; the only HTML it serves is the pair of Stripe return pages, which are
 * self-contained apart from their inline <style>. `frameAncestors: none` stops
 * those pages being framed for clickjacking during a checkout return.
 */
export const securityHeaders: RequestHandler = helmet({
  hsts: { maxAge: 63_072_000, includeSubDomains: true, preload: true },
  contentSecurityPolicy: {
    useDefaults: false,
    directives: {
      defaultSrc: ["'none'"],
      styleSrc: ["'unsafe-inline'"], // the return pages' own <style> block
      imgSrc: ["'self'", 'data:'],
      frameAncestors: ["'none'"],
      baseUri: ["'none'"],
      formAction: ["'none'"],
    },
  },
  // The app is not a website and is never framed legitimately.
  crossOriginResourcePolicy: { policy: 'same-site' },
  // Hides the Express fingerprint; helmet also strips X-Powered-By.
  referrerPolicy: { policy: 'no-referrer' },
});

/**
 * CORS, closed by default.
 *
 * A native app sends no Origin header at all, so requests without one are
 * allowed - that is the overwhelming majority of real traffic and blocking it
 * would break the app. Requests that *do* carry an Origin must match the
 * allow-list exactly; anything else gets no CORS headers back, so the browser
 * refuses the response. The origin is never reflected unvalidated.
 */
export function cors(req: Request, res: Response, next: NextFunction) {
  const origin = req.headers.origin;

  if (origin && config.clientOrigins.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    // Tell caches that the response body varies by origin, or a CDN could
    // serve one origin's allowed response to another.
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    res.setHeader('Access-Control-Max-Age', '600');
  }

  // Preflight ends here either way. An unknown origin gets a bare 204 with no
  // allow headers, which is what makes the browser block the real request.
  if (req.method === 'OPTIONS') return res.status(204).end();
  next();
}

/**
 * Rate-limit key.
 *
 * Prefers the authenticated user id, so one account on a shared NAT cannot
 * spend everybody else's budget, and one user cannot multiply their own budget
 * by cycling IPs. Falls back to the IP for unauthenticated routes, which is
 * exactly where the auth limiter lives.
 *
 * `ipKeyGenerator` rather than `req.ip` directly: it normalises IPv6 to a /64
 * prefix, and without it a v6 client gets a fresh bucket per request simply by
 * varying the low bits of an address it already controls.
 */
function keyFor(req: Request): string {
  const user = (req as Request & { user?: { id?: string } }).user;
  return user?.id ?? ipKeyGenerator(req.ip ?? '');
}

const limiterDefaults = {
  standardHeaders: true as const,
  legacyHeaders: false as const,
  keyGenerator: keyFor,
  // A tripped limit is a security event, not just a 429. Logged so it can be
  // alerted on, which is the other half of the monitoring gap.
  handler: (req: Request, res: Response) => {
    console.warn('[ratelimit] tripped', {
      path: req.path,
      method: req.method,
      key: keyFor(req).slice(0, 12),
    });
    res.status(429).json({ error: 'too many requests, slow down' });
  },
};

/**
 * Sign-in. The tightest bucket in the app: these endpoints verify a third-party
 * token on every call, they are unauthenticated by necessity, and they are the
 * obvious target for credential stuffing. Ten attempts per quarter hour is
 * generous for a human and useless for a script.
 */
export const authLimiter = rateLimit({
  ...limiterDefaults,
  windowMs: 15 * 60_000,
  limit: 10,
});

/**
 * Anything that costs money or writes to a payment provider.
 */
export const billingLimiter = rateLimit({
  ...limiterDefaults,
  windowMs: 60_000,
  limit: 20,
});

/**
 * Writes: posting, messaging, reporting. High enough that a fast typer in a
 * busy room never notices, low enough that a script cannot flood a feed.
 */
export const writeLimiter = rateLimit({
  ...limiterDefaults,
  windowMs: 60_000,
  limit: 60,
});

/**
 * Everything else, as a backstop so no route is entirely unbounded.
 */
export const globalLimiter = rateLimit({
  ...limiterDefaults,
  windowMs: 60_000,
  limit: 300,
});
