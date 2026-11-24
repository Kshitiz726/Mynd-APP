import 'dotenv/config';

// Dev mode: the server boots with ZERO cloud credentials so you can run and
// exercise the realtime layer (presence, timers, sockets) immediately. As soon
// as you set DATABASE_URL / REDIS_URL / LiveKit keys, those subsystems switch
// from in-memory dev fallbacks to the real cloud services. Nothing is required.
const databaseUrl = process.env.DATABASE_URL ?? '';
const redisUrl = process.env.REDIS_URL ?? '';
const lkUrl = process.env.LK_URL ?? '';
const lkKey = process.env.LK_API_KEY ?? '';
const lkSecret = process.env.LK_API_SECRET ?? '';
const stripeSecret = process.env.STRIPE_SECRET_KEY ?? '';

// Where browser clients are allowed to call us from.
//
// The default used to be '*', which is fine on a laptop and wrong the moment it
// ships: an unset CLIENT_ORIGIN in production served
// `Access-Control-Allow-Origin: *` to every caller, so any web page on the
// internet could script the API. The default is now the closed one, and
// production refuses to start without an explicit value - a missing env var
// should stop a deploy, not silently widen it. Comma-separated for the handful
// of legitimate origins (site, admin, local web build).
function resolveClientOrigins(): string[] {
  const raw = (process.env.CLIENT_ORIGIN ?? '').trim();
  if (raw) return raw.split(',').map((s) => s.trim()).filter(Boolean);
  if (process.env.NODE_ENV === 'production') {
    throw new Error(
      'CLIENT_ORIGIN must be set in production (comma-separated list of allowed origins). ' +
        'Refusing to start with a wildcard CORS policy.',
    );
  }
  // Dev only: the Flutter web build and the local tooling.
  return ['http://localhost:8080', 'http://localhost:5000', 'http://127.0.0.1:8080'];
}

export const config = {
  port: Number(process.env.PORT ?? 8080),
  isProd: process.env.NODE_ENV === 'production',
  clientOrigins: resolveClientOrigins(),

  // In dev (no DB) the server trusts JWTs signed with this secret and builds the
  // user from the token claims. In prod, set JWT_SECRET to your Supabase secret.
  jwtSecret: process.env.JWT_SECRET ?? 'dev-insecure-secret-change-me',
  jwtIssuer: process.env.JWT_ISSUER ?? 'ourmynd',

  // The coach model provider's key. Server-side only, deliberately: it used to
  // be compiled into the app with --dart-define, where it was recoverable from
  // the binary. See routes/coach.ts.
  groqApiKey: process.env.GROQ_API_KEY ?? '',

  // Real Google OAuth: the Web Client ID from Google Cloud Console. The client
  // sends a Google ID token; the server verifies its signature + audience here.
  googleClientId: process.env.GOOGLE_CLIENT_ID ?? '',

  // Desktop (Windows/Linux) OAuth: the "Desktop app" client id + secret. The
  // desktop app does a loopback flow and hands us the auth code; we exchange it
  // here (secret stays server-side) and accept this id as a valid token audience.
  googleDesktopClientId: process.env.GOOGLE_DESKTOP_CLIENT_ID ?? '',
  googleDesktopClientSecret: process.env.GOOGLE_DESKTOP_CLIENT_SECRET ?? '',

  // Sign in with Apple. Apple addresses the identity token to the app's bundle
  // id, so that doubles as the audience we verify against — no client secret is
  // involved for plain sign-in, only Apple's public keys. (A .p8 key is needed
  // for token revocation, which App Store account-deletion will eventually
  // require; that is deliberately not wired here yet.)
  appleBundleId: process.env.APPLE_BUNDLE_ID ?? 'com.ourmynd.app',

  // The app's numeric App Store id, which is what Apple puts in a signed
  // StoreKit transaction rather than the bundle id. Not a secret - it is the
  // number in every App Store URL for the app - but it has to match, or every
  // production receipt fails verification with INVALID_APP_IDENTIFIER.
  appleAppStoreId: Number(process.env.APPLE_APP_STORE_ID ?? '6838455123'),

  // Web/Android Sign in with Apple addresses the token to the Services ID
  // rather than the bundle id, so both have to be accepted as audiences.
  appleServiceId: process.env.APPLE_SERVICE_ID ?? '',

  // Revocation credentials. The key is held as a PATH to a file outside the
  // repo, never as inline key material — see server/.env for why.
  appleTeamId: process.env.APPLE_TEAM_ID ?? '',
  appleKeyId: process.env.APPLE_KEY_ID ?? '',
  applePrivateKeyPath: process.env.APPLE_PRIVATE_KEY_PATH ?? '',

  // iOS OAuth: the "iOS" client id. Unlike Android - where serverClientId makes
  // Google mint a token addressed to the WEB client - the iOS SDK always
  // addresses the ID token to the iOS client itself, so it has to be accepted as
  // an audience in its own right or every iPhone sign-in fails verification.
  googleIosClientId: process.env.GOOGLE_IOS_CLIENT_ID ?? '',

  databaseUrl,
  redisUrl,
  livekit: { url: lkUrl, apiKey: lkKey, apiSecret: lkSecret },
  fcmServiceAccount: process.env.FCM_SA_JSON ?? '',

  // Discord presence bot. Purely cosmetic: it holds a gateway connection so the
  // OurMynd account shows as online at the top of the server's member list.
  // Discord only puts ONLINE members into a hoisted role group, so an invited
  // bot that never connects sits in Offline at the bottom, which is the whole
  // thing this exists to avoid.
  discordBotToken: process.env.DISCORD_BOT_TOKEN ?? '',

  // Stripe billing. The secret key stays server-side (never shipped to the app);
  // the publishable key is safe to hand the client. Webhook secret is optional -
  // when unset we reconcile by polling the Checkout Session on return instead.
  stripe: {
    secretKey: stripeSecret,
    publishableKey: process.env.STRIPE_PUBLISHABLE_KEY ?? '',
    webhookSecret: process.env.STRIPE_WEBHOOK_SECRET ?? '',
    prices: {
      plusMonthly: process.env.STRIPE_PRICE_PLUS_MONTHLY ?? '',
      plusYearly: process.env.STRIPE_PRICE_PLUS_YEARLY ?? '',
      proMonthly: process.env.STRIPE_PRICE_PRO_MONTHLY ?? '',
      proYearly: process.env.STRIPE_PRICE_PRO_YEARLY ?? '',
    },
  },

  // Feature flags derived from which creds are present.
  hasDb: !!databaseUrl,
  hasRedis: !!redisUrl,
  hasLivekit: !!(lkUrl && lkKey && lkSecret),
  hasGoogleAuth: !!process.env.GOOGLE_CLIENT_ID,
  hasStripe: !!stripeSecret,
  hasDiscord: !!process.env.DISCORD_BOT_TOKEN,
};

export function logMode() {
  if (config.isProd && config.jwtSecret === 'dev-insecure-secret-change-me') {
    console.warn('[config] WARNING: running in prod with the insecure dev JWT secret.');
  }
  console.log(
    `[config] db=${config.hasDb ? 'cloud' : 'in-memory(dev)'} ` +
      `redis=${config.hasRedis ? 'cloud' : 'in-memory(dev)'} ` +
      `livekit=${config.hasLivekit ? 'on' : 'off(dev)'} ` +
      `google-auth=${config.hasGoogleAuth ? 'on' : 'off'} ` +
      `stripe=${config.hasStripe ? 'on' : 'off'} ` +
      `discord=${config.hasDiscord ? 'on' : 'off'}`,
  );
}
