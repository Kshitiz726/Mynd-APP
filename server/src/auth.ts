import jwt from 'jsonwebtoken';
import { createPublicKey } from 'node:crypto';
import { Router, type Request, type Response, type NextFunction } from 'express';
import { OAuth2Client } from 'google-auth-library';
import { config } from './config.js';
import { db } from './db.js';

const googleClient = new OAuth2Client(config.googleClientId);

// A small palette so each new Google user gets a stable, pleasant avatar colour.
const AVATAR_COLORS = ['#6B70C9', '#F0A479', '#6FB28C', '#5C8AD0', '#B07CD6', '#E0598B'];
function colorFor(seed: string): string {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) | 0;
  return AVATAR_COLORS[Math.abs(h) % AVATAR_COLORS.length];
}

// Anonymous, Reddit-style display names (no "u/"): Adjective + Noun + number,
// e.g. "MellowOtter47". Every user is anonymous - we never store/show the real
// Google name. ~30×30×100 ≈ 90k combinations keeps collisions rare.
const ADJECTIVES = [
  'Calm', 'Quiet', 'Brave', 'Gentle', 'Mellow', 'Cosmic', 'Velvet', 'Lucid', 'Amber', 'Hazel',
  'Misty', 'Noble', 'Sunny', 'Dusky', 'Golden', 'Hidden', 'Indigo', 'Jolly', 'Lunar', 'Maple',
  'Nimble', 'Opal', 'Pebble', 'Silent', 'Tidal', 'Wander', 'Bramble', 'Cobalt', 'Ember', 'Frost',
];
const NOUNS = [
  'Otter', 'Maple', 'Fern', 'Heron', 'Willow', 'Comet', 'Pixel', 'Lynx', 'Sparrow', 'Birch',
  'Falcon', 'Cedar', 'Marble', 'Quartz', 'Raven', 'Sage', 'Tide', 'Vine', 'Wren', 'Yarrow',
  'Aspen', 'Bison', 'Crane', 'Echo', 'Grove', 'Harbor', 'Meadow', 'Nimbus', 'Orchid', 'Pine',
];
function randomUsername(): string {
  const a = ADJECTIVES[Math.floor(Math.random() * ADJECTIVES.length)];
  const n = NOUNS[Math.floor(Math.random() * NOUNS.length)];
  return `${a}${n}${Math.floor(Math.random() * 100)}`;
}

// Valid token audiences: the Web client id (web/Android), the Desktop client id,
// and the iOS client id. iOS needs its own entry because the Google iOS SDK
// addresses the ID token to the iOS client, not to the serverClientId the app
// passes - that one only buys a server auth code there.
function googleAudiences(): string[] {
  return [
    config.googleClientId,
    config.googleDesktopClientId,
    config.googleIosClientId,
  ].filter(Boolean) as string[];
}

// Verify a Google ID token's signature + audience, return the user's identity
// (email + the real Google display name). The name is stored but never shown -
// the public profile stays anonymous; see issueSessionForEmail.
async function verifyGoogleProfile(idToken: string): Promise<{ email: string; name: string | null }> {
  const ticket = await googleClient.verifyIdToken({ idToken, audience: googleAudiences() });
  const payload = ticket.getPayload();
  const email = payload?.email;
  if (!email) throw new Error('Google token has no email');
  return { email, name: payload?.name ?? null };
}

// --- Sign in with Apple ---------------------------------------------------
//
// Apple signs its identity tokens with rotating RSA keys published as a JWKS at
// the URL below. Verification needs no secret of ours: fetch the key whose kid
// matches the token header, check the signature, then check that the token was
// issued by Apple and addressed to our bundle id.
//
// Node can build a verifier straight from a JWK, so this needs no jwks client
// library on top of the jsonwebtoken we already depend on.
const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_ISSUER = 'https://appleid.apple.com';

type AppleJwk = { kid: string; kty: string; n: string; e: string; alg?: string };
let appleKeyCache: { keys: AppleJwk[]; fetchedAt: number } | null = null;

// Apple rotates these, so the cache is short and a cache miss on an unknown kid
// forces a refetch rather than failing a legitimate sign-in.
async function appleKeys(forceRefresh = false): Promise<AppleJwk[]> {
  const fresh = appleKeyCache && Date.now() - appleKeyCache.fetchedAt < 60 * 60 * 1000;
  if (fresh && !forceRefresh) return appleKeyCache!.keys;

  // Timed out explicitly. Node's fetch has no default timeout, so a hung
  // connection to Apple would hold a request - and its database connection -
  // open indefinitely; enough of them and the pool is gone. Every sign-in goes
  // through here, so this is the outbound call most worth bounding.
  const resp = await fetch(APPLE_KEYS_URL, { signal: AbortSignal.timeout(5_000) });
  if (!resp.ok) throw new Error(`Apple JWKS fetch failed: ${resp.status}`);
  const body = (await resp.json()) as { keys: AppleJwk[] };
  appleKeyCache = { keys: body.keys ?? [], fetchedAt: Date.now() };
  return appleKeyCache.keys;
}

async function applePublicKeyPem(kid: string): Promise<string> {
  let jwk = (await appleKeys()).find((k) => k.kid === kid);
  if (!jwk) jwk = (await appleKeys(true)).find((k) => k.kid === kid);
  if (!jwk) throw new Error(`no Apple key for kid ${kid}`);
  return createPublicKey({ key: jwk as never, format: 'jwk' })
    .export({ type: 'spki', format: 'pem' })
    .toString();
}

// Verify an Apple identity token and pull out the account's email.
//
// Apple only sends the email on the FIRST authorisation for an account; every
// later sign-in omits the name entirely and, for "Hide My Email" users, the
// address is a stable private relay one. Either way the `sub` claim is the
// durable identity, so callers fall back to it when there is no email.
async function verifyAppleProfile(
  identityToken: string,
): Promise<{ email: string | null; sub: string }> {
  const decoded = jwt.decode(identityToken, { complete: true });
  const kid = decoded?.header?.kid;
  if (!kid) throw new Error('Apple token has no kid');

  // Native iOS tokens are addressed to the bundle id; web/Android ones to the
  // Services ID. Accept both, and nothing else.
  // Typed as a non-empty tuple: jwt.verify rejects a plain string[], and the
  // bundle id is always present, so the first element is guaranteed.
  const audiences: [string, ...string[]] = [
    config.appleBundleId,
    ...(config.appleServiceId ? [config.appleServiceId] : []),
  ];

  const payload = jwt.verify(identityToken, await applePublicKeyPem(kid), {
    algorithms: ['RS256'],
    issuer: APPLE_ISSUER,
    audience: audiences,
  }) as jwt.JwtPayload;

  if (!payload.sub) throw new Error('Apple token has no sub');
  return { email: (payload.email as string) ?? null, sub: payload.sub };
}

// Upsert the user (keyed by email) with a stable anonymous username, mint our
// 30-day session JWT, and send it. Shared by every Google sign-in path.
//
// Dedup is select-first (not just ON CONFLICT): an older `users` table that was
// created before the `handle unique` constraint won't satisfy ON CONFLICT and
// would silently insert a *new* row on every login - the "same Gmail makes a new
// user each time" bug. Selecting the earliest row by handle guarantees one
// stable identity per email regardless of the constraint's presence, and
// tolerates any pre-existing duplicates (limit 1).
async function issueSessionForEmail(
  res: Response,
  email: string,
  seed: string,
  fullName: string | null = null,
): Promise<void> {
  let u = await db.oneOrNone(
    `select * from users where handle = $1 order by created_at asc limit 1`,
    [email],
  );
  if (u) {
    // Returning user: load the SAME account and refresh stored identity. This is
    // what makes "continue with Google again" restore everything - same user id,
    // so all their posts, friends, chats, rooms and notifications come back.
    await db.none(
      `update users set last_seen_at = now(),
              email = $2,
              full_name = coalesce($3, full_name)
       where id = $1`,
      [u.id, email, fullName],
    );
  } else {
    u = await db.one(
      `insert into users (handle, display_name, avatar_color, avatar_text_color, email, full_name)
         values ($1, $2, $3, '#FFFFFF', $4, $5)
       on conflict (handle) do update set last_seen_at = now()
       returning *`,
      [email, randomUsername(), colorFor(seed), email, fullName],
    );
  }
  u = publicUser(u);
  res.json({ ...(await issueTokens(u)), user: u });
}

// ── Access and refresh tokens ───────────────────────────────────────────────
//
// This used to be one 30-day bearer token with no way to end it early. Two
// separate problems: a token captured from a device backup stayed valid for a
// month, and signing out only forgot the local copy, so "sign me out" was a
// statement about this phone rather than about the session.
//
// Split into a short access token and a long refresh token, both carrying the
// account's `token_version`. Bumping that column invalidates everything already
// issued, in one statement, with no deny-list to maintain or expire.

/** Long enough not to interrupt a coaching conversation, short enough to matter. */
const ACCESS_TTL = '30m';

/** The refresh token's life, and so the real "stay signed in" window. */
const REFRESH_TTL = '30d';

export interface TokenPair {
  token: string;
  refreshToken: string;
  expiresIn: number;
}

/** Current revocation counter for an account. */
async function tokenVersion(userId: string): Promise<number> {
  if (!config.hasDb) return 0;
  const row = await db.oneOrNone(`select token_version from users where id = $1`, [userId]);
  return row?.token_version ?? 0;
}

/**
 * Mint a fresh pair. `typ` separates the two so a refresh token cannot be
 * presented as an access token: they are signed with the same secret, and
 * without this claim the long-lived one would open every authenticated route
 * and the split would buy nothing.
 */
async function issueTokens(u: { id: string; display_name: string; handle: string; avatar_color: string | null }): Promise<TokenPair> {
  const ver = await tokenVersion(u.id);
  const token = jwt.sign(
    { sub: u.id, name: u.display_name, handle: u.handle, color: u.avatar_color, ver, typ: 'access' },
    config.jwtSecret,
    { expiresIn: ACCESS_TTL, issuer: config.jwtIssuer },
  );
  const refreshToken = jwt.sign(
    { sub: u.id, ver, typ: 'refresh' },
    config.jwtSecret,
    { expiresIn: REFRESH_TTL, issuer: config.jwtIssuer },
  );
  return { token, refreshToken, expiresIn: 30 * 60 };
}

/**
 * Invalidate every token this account currently holds.
 *
 * Called on sign-out and on account deletion. Idempotent, and cheap: one
 * increment, no rows to scan.
 */
export async function revokeAllTokens(userId: string): Promise<void> {
  if (!config.hasDb) return;
  await db.none(`update users set token_version = token_version + 1 where id = $1`, [userId]);
}

export interface AuthUser {
  id: string;
  handle: string;
  displayName: string;
  initial: string;
  avatarColor: string | null;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request { user: AuthUser }
  }
}

/**
 * Verify a JWT (Supabase Auth token or our own) and hydrate the user row.
 * The `sub` claim is the user id - Supabase puts the auth.uid() there.
 */
export async function verifyJwt(token?: string): Promise<AuthUser> {
  if (!token) throw new Error('missing token');
  const raw = token.startsWith('Bearer ') ? token.slice(7) : token;
  // `issuer` is now asserted here too. It was set when signing and never
  // checked, so a token minted by anything else sharing the secret would have
  // been accepted on its signature alone.
  const decoded = jwt.verify(raw, config.jwtSecret, { issuer: config.jwtIssuer }) as {
    sub: string;
    name?: string;
    handle?: string;
    color?: string;
    ver?: number;
    typ?: string;
  };

  // A refresh token is not an access token. Without this check the 30-day
  // credential would authenticate every route and splitting them would have
  // achieved nothing. Tokens minted before this change carry no `typ` and are
  // still accepted, so existing sessions are not force-signed-out by the
  // deploy; remove the `!== undefined` allowance once they have aged out.
  if (decoded.typ !== undefined && decoded.typ !== 'access') {
    throw new Error('not an access token');
  }

  // Dev mode (no DB): trust the signed claims and synthesize the user, so the
  // realtime layer is fully exercisable without a database.
  if (!config.hasDb) {
    const name = decoded.name ?? 'Dev User';
    return {
      id: decoded.sub,
      handle: decoded.handle ?? decoded.sub,
      displayName: name,
      initial: name.charAt(0).toUpperCase(),
      avatarColor: decoded.color ?? '#6366F1',
    };
  }

  const u = await db.oneOrNone(
    `select id, handle, display_name, initial, avatar_color, token_version
       from users where id = $1`,
    [decoded.sub],
  );
  if (!u) throw new Error('user not found');

  // The revocation check. A token whose version is behind the account's was
  // issued before the last sign-out or deletion, and is refused however valid
  // its signature and expiry still are.
  if (decoded.ver !== undefined && decoded.ver !== u.token_version) {
    throw new Error('token revoked');
  }

  return {
    id: u.id,
    handle: u.handle,
    displayName: u.display_name,
    initial: u.initial,
    avatarColor: u.avatar_color,
  };
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  verifyJwt(req.headers.authorization)
    .then((user) => { req.user = user; next(); })
    .catch(() => res.status(401).json({ error: 'unauthorized' }));
}

export const authRouter = Router();

/**
 * REAL Google sign-in. The Flutter client (web GIS / native) sends the Google
 * ID token; we verify its signature + audience against our Web Client ID, then
 * upsert the user (keyed by their Google email) and mint our own 30-day JWT.
 */
authRouter.post('/auth/google', async (req, res) => {
  const { idToken } = req.body ?? {};
  if (!idToken) return res.status(400).json({ error: 'missing idToken' });
  if (!config.hasGoogleAuth) {
    return res.status(503).json({ error: 'GOOGLE_CLIENT_ID not configured on the server' });
  }
  if (!config.hasDb) {
    return res.status(503).json({ error: 'DATABASE_URL not configured - run `npm run dev:full`' });
  }

  let profile: { email: string; name: string | null };
  try {
    profile = await verifyGoogleProfile(idToken);
  } catch (e) {
    console.error('Google token verification failed:', e);
    return res.status(401).json({ error: 'invalid Google token' });
  }

  try {
    await issueSessionForEmail(res, profile.email, profile.email, profile.name);
  } catch (e) {
    console.error('Google auth error:', e);
    res.status(500).json({ error: 'internal server error' });
  }
});

/**
 * REAL Sign in with Apple. The iOS client sends Apple's identity token; we
 * verify its signature against Apple's published keys and check it was issued
 * to our bundle id, then issue our own session exactly as the Google path does.
 *
 * Apple gives a real address only on the first authorisation, and a private
 * relay address for "Hide My Email" users. On every later sign-in there is no
 * email at all, so the account is keyed on the stable `sub` claim rendered as
 * an apple.local address — that keeps one durable identity per Apple ID rather
 * than minting a fresh user whenever Apple stays quiet. The display name is
 * left null: profiles here are anonymous by design.
 */
authRouter.post('/auth/apple', async (req, res) => {
  const { identityToken } = req.body ?? {};
  if (!identityToken) return res.status(400).json({ error: 'missing identityToken' });
  if (!config.hasDb) {
    return res.status(503).json({ error: 'DATABASE_URL not configured - run `npm run dev:full`' });
  }

  let profile: { email: string | null; sub: string };
  try {
    profile = await verifyAppleProfile(identityToken);
  } catch (e) {
    console.error('Apple token verification failed:', e);
    return res.status(401).json({ error: 'invalid Apple token' });
  }

  try {
    const handle = profile.email ?? `${profile.sub}@apple.local`;
    await issueSessionForEmail(res, handle, handle, null);
  } catch (e) {
    console.error('Apple auth error:', e);
    res.status(500).json({ error: 'internal server error' });
  }
});

/**
 * REAL Google sign-in for desktop (Windows/Linux). The app runs the loopback
 * OAuth flow and sends us the auth code; we exchange it with the desktop client
 * secret (kept server-side), verify the ID token, then issue our session.
 */
authRouter.post('/auth/google/desktop', async (req, res) => {
  const { code, codeVerifier, redirectUri } = req.body ?? {};
  if (!code || !codeVerifier || !redirectUri) return res.status(400).json({ error: 'missing fields' });
  if (!config.googleDesktopClientId) {
    return res.status(503).json({ error: 'GOOGLE_DESKTOP_CLIENT_ID not configured on the server' });
  }
  if (!config.hasDb) return res.status(503).json({ error: 'DATABASE_URL not configured - run `npm run dev:full`' });

  let idToken: string;
  try {
    // PKCE flow - the client secret is optional (modern Desktop clients are
    // PKCE-only and have none); include it only if one is configured.
    const form: Record<string, string> = {
      code,
      code_verifier: codeVerifier,
      redirect_uri: redirectUri,
      client_id: config.googleDesktopClientId,
      grant_type: 'authorization_code',
    };
    if (config.googleDesktopClientSecret) form.client_secret = config.googleDesktopClientSecret;
    const r = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(form),
      signal: AbortSignal.timeout(10_000),
    });
    const j = (await r.json()) as { id_token?: string; error?: string };
    if (!r.ok || !j.id_token) {
      console.error('Desktop token exchange failed:', j);
      return res.status(401).json({ error: 'token exchange failed' });
    }
    idToken = j.id_token;
  } catch (e) {
    console.error('Desktop token endpoint error:', e);
    return res.status(502).json({ error: 'google token endpoint error' });
  }

  let profile: { email: string; name: string | null };
  try {
    profile = await verifyGoogleProfile(idToken);
  } catch (e) {
    console.error('Desktop token verification failed:', e);
    return res.status(401).json({ error: 'invalid Google token' });
  }

  try {
    await issueSessionForEmail(res, profile.email, profile.email, profile.name);
  } catch (e) {
    console.error('Desktop Google auth error:', e);
    res.status(500).json({ error: 'internal server error' });
  }
});


/**
 * Trade a refresh token for a new pair.
 *
 * Rotating: the old refresh token is not reusable, because the pair is minted
 * against the account's current `token_version` and the caller is handed a
 * fresh one each time. A stolen refresh token is therefore only useful until
 * the legitimate device next refreshes or signs out.
 */
authRouter.post('/auth/refresh', async (req, res) => {
  const presented = String(req.body?.refreshToken ?? '');
  if (!presented) return res.status(400).json({ error: 'missing refreshToken' });

  try {
    const decoded = jwt.verify(presented, config.jwtSecret, {
      issuer: config.jwtIssuer,
    }) as { sub: string; ver?: number; typ?: string };

    // An access token must not buy a new session. Without this the 30-minute
    // credential could be rolled forward forever and would be as good as the
    // 30-day one.
    if (decoded.typ !== 'refresh') {
      return res.status(401).json({ error: 'not a refresh token' });
    }

    const u = await db.oneOrNone(
      `select id, handle, display_name, avatar_color, token_version from users where id = $1`,
      [decoded.sub],
    );
    if (!u) return res.status(401).json({ error: 'unknown account' });
    if (decoded.ver !== undefined && decoded.ver !== u.token_version) {
      return res.status(401).json({ error: 'token revoked' });
    }

    res.json(await issueTokens(u));
  } catch {
    // Deliberately uniform: expired, forged and revoked all answer the same,
    // so the endpoint cannot be used to probe which accounts exist.
    res.status(401).json({ error: 'invalid refresh token' });
  }
});

/**
 * Sign out everywhere. Ends every session this account holds, not just the
 * caller's, which is the behaviour someone reaching for "sign out" on a lost
 * phone actually needs.
 */
authRouter.post('/auth/logout', requireAuth, async (req, res) => {
  try {
    await revokeAllTokens(req.user.id);
    res.json({ ok: true });
  } catch (e) {
    console.error('logout failed:', e);
    res.status(500).json({ error: 'internal server error' });
  }
});

authRouter.post('/auth/google-mock', async (req, res) => {
  // Dev only. This mints a full session from nothing but a handle - no
  // credential, no token, no proof of anything - so in production it is an
  // account takeover for any address an attacker can guess. It was reachable
  // on the live server because only devRoutes is gated by !isProd, and this
  // sits on authRouter, which mounts unconditionally.
  //
  // It only failed there by accident: issueTokens reads users.token_version,
  // which did not exist yet, so it 500'd instead of handing out a session.
  // Running the migration would have quietly turned it into a working bypass.
  if (config.isProd) return res.status(404).json({ error: 'not found' });

  const { handle } = req.body;
  if (!handle) return res.status(400).json({ error: 'missing handle' });

  try {
    let u = await db.oneOrNone('select * from users where handle = $1', [handle]);
    if (!u) {
      // Anonymous username, same as the real flow (client-sent name is ignored).
      u = await db.one(
        `insert into users (handle, display_name, avatar_color, avatar_text_color)
         values ($1, $2, $3, '#FFFFFF') returning *`,
        [handle, randomUsername(), colorFor(handle)]
      );
    }

    // Same issuance as every real path, so the dev route cannot hand out a
    // long-lived token that the production rules would never mint.
    res.json({ ...(await issueTokens(u)), user: publicUser(u) });
  } catch (e) {
    console.error('Google mock auth error:', e);
    res.status(500).json({ error: 'internal server error' });
  }
});

/**
 * A user row as it may leave the server.
 *
 * `select *` and `returning *` both carry `avatar_image`, which is the picture
 * itself and has no business inside a sign-in response. Strip it and hand back
 * the URL that serves it instead.
 *
 * Shared by every auth path on purpose: the mock endpoint used to shape its own
 * response, so a client talking to it saw a different user object than the real
 * Google flow returns, which is exactly the kind of difference you only find
 * when it is already confusing you.
 */
export function publicUser(u: any) {
  const { avatar_image, ...rest } = u;
  return {
    ...rest,
    avatar_url: avatar_image
      ? `/api/users/${u.id}/avatar?v=${new Date(u.avatar_updated_at ?? 0).getTime()}`
      : null,
  };
}
