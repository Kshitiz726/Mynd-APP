/**
 * Apple purchase verification smoke test — proves the StoreKit side works
 * with no credentials, no network and no App Store Connect access.
 *
 * It can do that because the App Store library deliberately skips certificate
 * verification for the Xcode environment, where transactions come from a local
 * .storekit file and are not signed by Apple at all. That lets this script
 * mint payloads and drive the real verifier, the real mapping and the real
 * entitlement rules — everything except the signature arithmetic, which the
 * forgery cases below cover from the other side.
 *
 * Run:  node --import tsx scripts/smoke_apple.ts
 * Must NOT be run with NODE_ENV=production: the server refuses Xcode
 * transactions there, which is the point of that refusal.
 */
import {
  entitlementIsLive,
  notificationLeavesEntitlement,
  verifySignedNotification,
  verifySignedTransaction,
  type AppleNotification,
  type AppleTransaction,
} from '../src/services/apple.js';

const BUNDLE_ID = 'com.ourmynd.app';
const PRODUCT = 'com.ourmynd.app.pro.yearly';

let passed = 0;
let failed = 0;
function expect(cond: boolean, msg: string) {
  console.log(`${cond ? '✅' : '❌'} ${msg}`);
  if (cond) passed++;
  else failed++;
}

async function expectRejected(fn: () => Promise<unknown>, msg: string) {
  try {
    await fn();
    expect(false, `${msg} (it was accepted)`);
  } catch {
    expect(true, msg);
  }
}

const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');

/** A JWS whose signature is nonsense, which is all the Xcode path needs. */
const jws = (payload: unknown) =>
  `${b64({ alg: 'ES256', x5c: [] })}.${b64(payload)}.not-a-signature`;

const hoursFromNow = (h: number) => Date.now() + h * 3600_000;

function txPayload(over: Record<string, unknown> = {}) {
  return {
    bundleId: BUNDLE_ID,
    environment: 'Xcode',
    productId: PRODUCT,
    transactionId: '2000000900000001',
    originalTransactionId: '2000000800000001',
    purchaseDate: Date.now(),
    expiresDate: hoursFromNow(24),
    type: 'Auto-Renewable Subscription',
    inAppOwnershipType: 'PURCHASED',
    signedDate: Date.now(),
    ...over,
  };
}

function notificationPayload(
  type: string,
  opts: { tx?: Record<string, unknown>; graceHours?: number; subtype?: string } = {},
) {
  return {
    notificationType: type,
    ...(opts.subtype ? { subtype: opts.subtype } : {}),
    notificationUUID: '00000000-0000-0000-0000-000000000001',
    version: '2.0',
    signedDate: Date.now(),
    data: {
      bundleId: BUNDLE_ID,
      environment: 'Xcode',
      signedTransactionInfo: jws(txPayload(opts.tx)),
      signedRenewalInfo: jws({
        environment: 'Xcode',
        originalTransactionId: '2000000800000001',
        productId: PRODUCT,
        autoRenewStatus: 1,
        signedDate: Date.now(),
        ...(opts.graceHours === undefined
          ? {}
          : { gracePeriodExpiresDate: hoursFromNow(opts.graceHours) }),
      }),
    },
  };
}

async function main() {
  console.log('\n— a forged receipt gets nothing —');
  // The whole security model in two assertions: without Apple's signature the
  // payload is worthless, whatever it claims to contain.
  await expectRejected(() => verifySignedTransaction('not.a.jws'), 'garbage is refused');
  await expectRejected(
    () => verifySignedTransaction(jws(txPayload({ environment: 'Production' }))),
    'an unsigned transaction claiming Production is refused',
  );
  await expectRejected(
    () => verifySignedTransaction(jws(txPayload({ bundleId: 'com.someone.else' }))),
    "another app's bundle id is refused",
  );

  console.log('\n— what a verified transaction says —');
  const tx = await verifySignedTransaction(jws(txPayload()));
  expect(tx.productId === PRODUCT, 'the product comes out of the signature');
  expect(tx.originalTransactionId === '2000000800000001', 'the subscription identity survives');
  expect(tx.revokedAt === null, 'an ordinary purchase is not revoked');
  expect(entitlementIsLive(tx), 'an unexpired purchase entitles');

  const expired = await verifySignedTransaction(
    jws(txPayload({ expiresDate: hoursFromNow(-1) })),
  );
  expect(!entitlementIsLive(expired), 'an expired purchase does not entitle');

  // The hole this closes: buy a year, ask Apple for a refund, press Restore.
  // The expiry is still a year away, so expiry alone would hand it back.
  const refunded = await verifySignedTransaction(
    jws(txPayload({ revocationDate: Date.now(), revocationReason: 1 })),
  );
  expect(refunded.revokedAt !== null, 'a refund is visible in the transaction');
  expect(
    !entitlementIsLive(refunded),
    'a refunded purchase does not entitle, even though it has not expired',
  );

  console.log('\n— what a notification does to entitlement —');
  const note = (p: unknown) => verifySignedNotification(jws(p)) as Promise<AppleNotification>;

  const renewed = await note(notificationPayload('DID_RENEW'));
  expect(renewed.type === 'DID_RENEW', 'the event type is read');
  expect(renewed.transaction !== null, 'the nested transaction is decoded too');
  expect(notificationLeavesEntitlement(renewed), 'a renewal keeps the subscriber paid');

  const gone = await note(
    notificationPayload('EXPIRED', { tx: { expiresDate: hoursFromNow(-1) } }),
  );
  expect(!notificationLeavesEntitlement(gone), 'an expiry ends it');

  const refundNote = await note(
    notificationPayload('REFUND', { tx: { revocationDate: Date.now() } }),
  );
  expect(!notificationLeavesEntitlement(refundNote), 'a refund ends it immediately');

  // A failed card with the grace period switched on. The transaction has
  // already expired, so reading only the transaction would cut off somebody
  // Apple is still charging on behalf of.
  const grace = await note(
    notificationPayload('DID_FAIL_TO_RENEW', {
      subtype: 'GRACE_PERIOD',
      tx: { expiresDate: hoursFromNow(-1) },
      graceHours: 48,
    }),
  );
  expect(grace.gracePeriodExpiresAt !== null, 'the grace period is read');
  expect(
    notificationLeavesEntitlement(grace),
    'a subscriber inside the billing grace period keeps access',
  );

  const graceOver = await note(
    notificationPayload('GRACE_PERIOD_EXPIRED', {
      tx: { expiresDate: hoursFromNow(-72) },
      graceHours: -1,
    }),
  );
  expect(!notificationLeavesEntitlement(graceOver), 'an elapsed grace period ends it');

  // No grace on a refund, however much time is left on the clock.
  const refundInGrace = await note(
    notificationPayload('REFUND', {
      tx: { revocationDate: Date.now() },
      graceHours: 48,
    }),
  );
  expect(
    !notificationLeavesEntitlement(refundInGrace),
    'a refund beats an unexpired grace period',
  );

  const empty: AppleNotification = {
    type: 'TEST',
    subtype: null,
    uuid: null,
    transaction: null as AppleTransaction | null,
    gracePeriodExpiresAt: null,
  };
  expect(!notificationLeavesEntitlement(empty), 'a notification with no transaction grants nothing');

  await productionRefusesUnsignedData();

  console.log(`\n${failed === 0 ? '✅' : '❌'} ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exitCode = 1;
}

/**
 * The single most dangerous line in apple.ts, checked rather than trusted.
 *
 * Everything above this point relies on the Xcode environment, where the
 * library skips signature verification because the data came from a .storekit
 * file on a developer's machine. That is correct for a simulator and
 * catastrophic for a public server: anybody could POST one of these payloads
 * to Render and hand themselves a subscription for ever. allowedEnvironments()
 * is what stops that, by admitting Xcode only when the server is not in
 * production.
 *
 * It has to run in a child process because config.isProd is read from the
 * environment once, at import.
 */
async function productionRefusesUnsignedData() {
  console.log('\n— and none of that works in production —');

  if (process.env.SMOKE_APPLE_PROD === '1') return; // the child never recurses

  const { execFileSync } = await import('node:child_process');
  const probe = `
    import { verifySignedNotification, verifySignedTransaction } from '../src/services/apple.js';
    const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const jws = (p) => b64({ alg: 'ES256', x5c: [] }) + '.' + b64(p) + '.not-a-signature';
    const tx = {
      bundleId: '${BUNDLE_ID}', environment: 'Xcode', productId: '${PRODUCT}',
      transactionId: '1', originalTransactionId: '1',
      purchaseDate: Date.now(), expiresDate: Date.now() + 3600000,
      type: 'Auto-Renewable Subscription', inAppOwnershipType: 'PURCHASED',
      signedDate: Date.now(),
    };
    const out = [];
    try { await verifySignedTransaction(jws(tx)); out.push('TX_ACCEPTED'); }
    catch { out.push('TX_REFUSED'); }
    try {
      await verifySignedNotification(jws({
        notificationType: 'DID_RENEW', version: '2.0', signedDate: Date.now(),
        notificationUUID: '00000000-0000-0000-0000-000000000001',
        data: { bundleId: '${BUNDLE_ID}', environment: 'Xcode', signedTransactionInfo: jws(tx) },
      }));
      out.push('NOTE_ACCEPTED');
    } catch { out.push('NOTE_REFUSED'); }
    console.log(out.join(' '));
  `;

  const result = execFileSync(
    process.execPath,
    ['--import', 'tsx', '--input-type=module', '-e', probe],
    {
      cwd: new URL('.', import.meta.url).pathname,
      env: {
        ...process.env,
        NODE_ENV: 'production',
        SMOKE_APPLE_PROD: '1',
        // Not secrets, and nothing here ever listens or connects: the
        // production config refuses to load without them, which is itself a
        // good thing and simply has to be satisfied to get at the verifier.
        CLIENT_ORIGIN: 'https://example.invalid',
        JWT_SECRET: 'smoke-test-not-a-real-secret',
      },
      encoding: 'utf8',
    },
  );

  expect(
    result.includes('TX_REFUSED'),
    'a production server refuses an unsigned Xcode transaction',
  );
  expect(
    result.includes('NOTE_REFUSED'),
    'a production server refuses an unsigned Xcode notification',
  );
}

main().catch((err) => {
  console.error('smoke failed:', err);
  process.exitCode = 1;
});
