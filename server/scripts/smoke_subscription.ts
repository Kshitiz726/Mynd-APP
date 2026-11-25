/**
 * The whole subscription system, end to end, over real HTTP.
 *
 * Unlike smoke_apple.ts - which tests the verifier in isolation - this drives
 * the running server: authentication, the verify endpoint, the database write,
 * the status the app reads back, and the notification endpoint that moves
 * entitlement afterwards. If this passes, somebody who pays gets Pro and
 * somebody who stops paying stops having it.
 *
 * It works because the App Store library skips signature checks for the Xcode
 * environment, so transactions can be minted here. The production server
 * refuses that environment outright (smoke_apple.ts proves it), which is why
 * this is a development-stack test and not something that could be pointed at
 * Render.
 *
 * Run with the dev stack up (npm run dev:full):
 *   npm run smoke:subscription
 */
const BASE = process.env.SMOKE_URL ?? 'http://localhost:8080';
const BUNDLE_ID = 'com.ourmynd.app';
const MONTHLY = 'com.ourmynd.app.pro.monthly';
const YEARLY = 'com.ourmynd.app.pro.yearly';

let passed = 0;
let failed = 0;
function expect(cond: boolean, msg: string, got?: unknown) {
  console.log(`${cond ? '✅' : '❌'} ${msg}${cond || got === undefined ? '' : `  (got ${JSON.stringify(got)})`}`);
  cond ? passed++ : failed++;
}

const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
const jws = (p: unknown) => `${b64({ alg: 'ES256', x5c: [] })}.${b64(p)}.unsigned`;
const hours = (h: number) => Date.now() + h * 3600_000;

/** A transaction as StoreKit would hand it to the app, Xcode-environment. */
function tx(over: Record<string, unknown> = {}) {
  return jws({
    bundleId: BUNDLE_ID,
    environment: 'Xcode',
    productId: YEARLY,
    transactionId: String(Date.now()),
    originalTransactionId: 'orig-smoke-1',
    purchaseDate: Date.now(),
    expiresDate: hours(24),
    type: 'Auto-Renewable Subscription',
    inAppOwnershipType: 'PURCHASED',
    signedDate: Date.now(),
    ...over,
  });
}

function notification(type: string, over: Record<string, unknown> = {}) {
  return jws({
    notificationType: type,
    notificationUUID: '00000000-0000-0000-0000-00000000000' + (Math.floor(Math.random() * 9) + 1),
    version: '2.0',
    signedDate: Date.now(),
    data: {
      bundleId: BUNDLE_ID,
      environment: 'Xcode',
      signedTransactionInfo: tx(over),
    },
  });
}

async function devToken(user: string): Promise<string> {
  const r = await fetch(`${BASE}/api/dev/token?user=${user}`);
  if (!r.ok) throw new Error(`dev token for ${user}: ${r.status}`);
  return (await r.json()).token;
}

async function post(path: string, token: string | null, body: unknown) {
  const r = await fetch(BASE + path, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json().catch(() => null) };
}

async function status(token: string) {
  const r = await fetch(`${BASE}/api/billing/status`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return { status: r.status, body: await r.json().catch(() => null) };
}

async function main() {
  const sam = await devToken('sam');
  const maya = await devToken('maya');

  console.log('\n— before anybody pays —');
  let s = await status(sam);
  expect(s.body?.premium === false && s.body?.tier === 'free', 'a new account is free', s.body);

  console.log('\n— a forged receipt buys nothing —');
  let r = await post('/api/billing/apple/verify', sam, { receipt: 'garbage' });
  expect(r.status === 400, 'garbage is refused with 400', r.status);
  s = await status(sam);
  expect(s.body?.tier === 'free', 'and the account is still free', s.body?.tier);

  r = await post('/api/billing/apple/verify', null, { receipt: tx() });
  expect(r.status === 401, 'an unauthenticated purchase is refused', r.status);

  console.log('\n— buying the yearly plan —');
  r = await post('/api/billing/apple/verify', sam, { receipt: tx() });
  expect(r.status === 200, 'the purchase is accepted', r.status);
  expect(r.body?.premium === true, 'the response says premium', r.body);
  expect(r.body?.tier === 'pro', 'tier is pro', r.body?.tier);
  expect(r.body?.interval === 'year', 'interval is year', r.body?.interval);

  s = await status(sam);
  expect(s.body?.premium === true, 'and it persisted: status reads premium', s.body);

  console.log('\n— the client cannot name its own tier —');
  // planId and productId in the body are ignored; only the signature counts.
  r = await post('/api/billing/apple/verify', sam, {
    receipt: tx({ productId: MONTHLY, originalTransactionId: 'orig-smoke-1' }),
    planId: 'pro_year',
    productId: YEARLY,
  });
  expect(r.body?.interval === 'month', 'the signed product wins over the claimed one', r.body?.interval);

  console.log('\n— one subscription, one account —');
  r = await post('/api/billing/apple/verify', maya, { receipt: tx() });
  expect(r.status === 409, 'a second account restoring the same purchase is refused', r.status);
  expect(r.body?.code === 'apple_already_claimed', 'with a code the app can explain', r.body?.code);
  s = await status(maya);
  expect(s.body?.tier === 'free', 'and that account stays free', s.body?.tier);

  console.log('\n— an unknown product —');
  r = await post('/api/billing/apple/verify', sam, {
    receipt: tx({ productId: 'com.ourmynd.app.pro.decade', originalTransactionId: 'orig-smoke-9' }),
  });
  expect(r.status === 400 && r.body?.code === 'apple_unknown_product', 'is refused, not guessed at', r.body);

  console.log('\n— restoring something that has expired —');
  r = await post('/api/billing/apple/verify', sam, {
    receipt: tx({ expiresDate: hours(-1) }),
  });
  expect(r.body?.premium === false, 'grants nothing', r.body);
  expect(r.body?.tier === 'free', 'and drops the account to free', r.body?.tier);

  console.log('\n— restoring something that was refunded —');
  // Buy again first, so there is something to lose.
  await post('/api/billing/apple/verify', sam, { receipt: tx() });
  r = await post('/api/billing/apple/verify', sam, {
    receipt: tx({ revocationDate: Date.now(), revocationReason: 1 }),
  });
  expect(r.body?.premium === false, 'grants nothing even though it has not expired', r.body);

  console.log('\n— Apple tells us a month later —');
  r = await post('/api/billing/apple/notifications', null, {
    signedPayload: notification('DID_RENEW', { expiresDate: hours(24 * 30) }),
  });
  expect(r.status === 200, 'the renewal is accepted without any authentication', r.status);
  s = await status(sam);
  expect(s.body?.premium === true, 'and the lapsed account is paid up again', s.body);

  r = await post('/api/billing/apple/notifications', null, {
    signedPayload: notification('EXPIRED', { expiresDate: hours(-1) }),
  });
  expect(r.status === 200, 'an expiry is accepted', r.status);
  s = await status(sam);
  expect(s.body?.premium === false, 'and the account drops to free', s.body);

  await post('/api/billing/apple/verify', sam, { receipt: tx() });
  r = await post('/api/billing/apple/notifications', null, {
    signedPayload: notification('REFUND', { revocationDate: Date.now() }),
  });
  expect(r.status === 200, 'a refund is accepted', r.status);
  s = await status(sam);
  expect(s.body?.premium === false, 'and access ends immediately, not at period end', s.body);

  r = await post('/api/billing/apple/notifications', null, { signedPayload: 'garbage' });
  expect(r.status === 400, 'a forged notification is refused', r.status);

  console.log(`\n${failed === 0 ? '✅' : '❌'} ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error('smoke failed:', e);
  process.exitCode = 1;
});
