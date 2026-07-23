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

export const config = {
  port: Number(process.env.PORT ?? 8080),
  isProd: process.env.NODE_ENV === 'production',
  clientOrigin: process.env.CLIENT_ORIGIN ?? '*',

  // In dev (no DB) the server trusts JWTs signed with this secret and builds the
  // user from the token claims. In prod, set JWT_SECRET to your Supabase secret.
  jwtSecret: process.env.JWT_SECRET ?? 'dev-insecure-secret-change-me',
  jwtIssuer: process.env.JWT_ISSUER ?? 'ourmynd',

  // Real Google OAuth: the Web Client ID from Google Cloud Console. The client
  // sends a Google ID token; the server verifies its signature + audience here.
  googleClientId: process.env.GOOGLE_CLIENT_ID ?? '',

  // Desktop (Windows/Linux) OAuth: the "Desktop app" client id + secret. The
  // desktop app does a loopback flow and hands us the auth code; we exchange it
  // here (secret stays server-side) and accept this id as a valid token audience.
  googleDesktopClientId: process.env.GOOGLE_DESKTOP_CLIENT_ID ?? '',
  googleDesktopClientSecret: process.env.GOOGLE_DESKTOP_CLIENT_SECRET ?? '',

  // iOS OAuth: the "iOS" client id. Unlike Android - where serverClientId makes
  // Google mint a token addressed to the WEB client - the iOS SDK always
  // addresses the ID token to the iOS client itself, so it has to be accepted as
  // an audience in its own right or every iPhone sign-in fails verification.
  googleIosClientId: process.env.GOOGLE_IOS_CLIENT_ID ?? '',

  databaseUrl,
  redisUrl,
  livekit: { url: lkUrl, apiKey: lkKey, apiSecret: lkSecret },
  fcmServiceAccount: process.env.FCM_SA_JSON ?? '',

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
      `stripe=${config.hasStripe ? 'on' : 'off'}`,
  );
}
