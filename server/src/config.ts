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

  databaseUrl,
  redisUrl,
  livekit: { url: lkUrl, apiKey: lkKey, apiSecret: lkSecret },
  fcmServiceAccount: process.env.FCM_SA_JSON ?? '',

  // Feature flags derived from which creds are present.
  hasDb: !!databaseUrl,
  hasRedis: !!redisUrl,
  hasLivekit: !!(lkUrl && lkKey && lkSecret),
  hasGoogleAuth: !!process.env.GOOGLE_CLIENT_ID,
};

export function logMode() {
  if (config.isProd && config.jwtSecret === 'dev-insecure-secret-change-me') {
    console.warn('[config] WARNING: running in prod with the insecure dev JWT secret.');
  }
  console.log(
    `[config] db=${config.hasDb ? 'cloud' : 'in-memory(dev)'} ` +
      `redis=${config.hasRedis ? 'cloud' : 'in-memory(dev)'} ` +
      `livekit=${config.hasLivekit ? 'on' : 'off(dev)'} ` +
      `google-auth=${config.hasGoogleAuth ? 'on' : 'off'}`,
  );
}
