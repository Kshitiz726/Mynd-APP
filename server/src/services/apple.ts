import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from '@apple/app-store-server-library';

import { config } from '../config.js';

/**
 * Apple's side of a purchase, verified.
 *
 * StoreKit 2 hands the app a JWS: the transaction, signed by Apple, with the
 * signing chain attached. That means verification is arithmetic rather than a
 * network call - no shared secret, no App Store Connect API key, no round trip
 * to Apple that can be down at the moment somebody is paying. All it needs is
 * Apple's public root certificates, which ship in certs/apple.
 *
 * It also means the verification has to actually happen here. The device can
 * say anything; the only thing that cannot be forged is Apple's signature.
 */

const here = dirname(fileURLToPath(import.meta.url));

/** Apple's public roots, as shipped in the repo. Read once. */
let rootsCache: Buffer[] | null = null;

function appleRoots(): Buffer[] {
  if (rootsCache) return rootsCache;
  // All four, because Apple's chains are not all rooted at the same one and
  // which root a given chain uses is Apple's business, not ours.
  const names = [
    'AppleComputerRootCertificate.cer',
    'AppleIncRootCertificate.cer',
    'AppleRootCA-G2.cer',
    'AppleRootCA-G3.cer',
  ];
  const dir = join(here, '..', '..', 'certs', 'apple');
  rootsCache = names.map((n) => readFileSync(join(dir, n)));
  return rootsCache;
}

/**
 * Which environments a receipt may claim to come from.
 *
 * Production and Sandbox are both real: the same binary produces Sandbox
 * transactions under TestFlight and Production ones from the App Store, and
 * nothing in the receipt tells us which to expect before we look.
 *
 * Xcode and LocalTesting are the dangerous pair. Those transactions come from
 * a StoreKit configuration file on a developer's machine and are NOT signed by
 * Apple - the library decodes them without verifying anything, which is right
 * for a simulator and catastrophic for a server. Anybody could mint one and
 * hand themselves a subscription. So they are accepted only when this server
 * is explicitly not in production.
 */
function allowedEnvironments(): Environment[] {
  const real = [Environment.PRODUCTION, Environment.SANDBOX];
  if (config.isProd) return real;
  return [...real, Environment.XCODE, Environment.LOCAL_TESTING];
}

const verifiers = new Map<Environment, SignedDataVerifier>();

function verifierFor(env: Environment): SignedDataVerifier {
  const hit = verifiers.get(env);
  if (hit) return hit;
  const v = new SignedDataVerifier(
    appleRoots(),
    // Online OCSP checks off. They add a network round trip and a new way for
    // a paying customer's purchase to fail, in exchange for catching a
    // revoked Apple intermediate - which has never happened and which Apple's
    // own guidance does not require for transaction verification.
    false,
    env,
    config.appleBundleId,
    config.appleAppStoreId,
  );
  verifiers.set(env, v);
  return v;
}

export class AppleVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AppleVerificationError';
  }
}

/** What we keep from a verified transaction. */
export interface AppleTransaction {
  /** Identity of the subscription across renewals, upgrades and restores. */
  originalTransactionId: string;
  /** Identity of this one payment. */
  transactionId: string;
  productId: string;
  /** When access runs out. Null for a product that does not expire. */
  expiresAt: Date | null;
  /** True while the subscription is in its introductory free period. */
  isTrial: boolean;
  /**
   * When Apple took the money back, if it ever did.
   *
   * A refund or a revocation ends access at the moment it happens, not at the
   * end of the period that was paid for - the period was not paid for any
   * more. Apple stamps this into the transaction itself, so it travels with
   * every later restore of the same purchase.
   */
  revokedAt: Date | null;
  environment: Environment;
}

/** The one place a verified payload becomes an [AppleTransaction]. */
function toAppleTransaction(payload: JWSTransactionDecodedPayload): AppleTransaction {
  const originalTransactionId = payload.originalTransactionId;
  const transactionId = payload.transactionId;
  const productId = payload.productId;
  if (!originalTransactionId || !transactionId || !productId) {
    throw new AppleVerificationError('verified transaction is missing its identifiers');
  }
  return {
    originalTransactionId,
    transactionId,
    productId,
    expiresAt: payload.expiresDate ? new Date(payload.expiresDate) : null,
    isTrial: payload.offerType === 1,
    revokedAt: payload.revocationDate ? new Date(payload.revocationDate) : null,
    environment: (payload.environment as Environment) ?? Environment.PRODUCTION,
  };
}

/**
 * Verify a StoreKit 2 signed transaction and return what it says.
 *
 * Throws [AppleVerificationError] rather than returning a flag, because every
 * caller of this has exactly one correct response to a receipt that does not
 * verify: refuse, and do not grant anything.
 */
export async function verifySignedTransaction(
  signedTransaction: string,
): Promise<AppleTransaction> {
  if (!signedTransaction || signedTransaction.split('.').length !== 3) {
    throw new AppleVerificationError('not a signed transaction');
  }

  let payload: JWSTransactionDecodedPayload | null = null;
  let lastError: unknown = null;

  // Try each permitted environment. There is no way to know from outside which
  // one a receipt belongs to, and Apple's own guidance is to try production
  // first and fall back - a sandbox receipt verified against production fails
  // on the certificate chain, not on anything we could have predicted.
  for (const env of allowedEnvironments()) {
    try {
      payload = await verifierFor(env).verifyAndDecodeTransaction(signedTransaction);
      break;
    } catch (err) {
      lastError = err;
    }
  }

  if (!payload) {
    throw new AppleVerificationError(
      `signature did not verify: ${lastError instanceof Error ? lastError.message : lastError}`,
    );
  }

  return toAppleTransaction(payload);
}

/**
 * Whether a verified transaction still entitles the user to anything.
 *
 * Two things end it, and they are not the same thing.
 *
 * Expiry is the ordinary one. A cancelled subscription keeps working until the
 * period it was paid for runs out, which is what Apple charges for and what
 * the customer expects; revoking at the moment of cancellation would be taking
 * back time somebody already bought.
 *
 * Revocation is the other, and it was missing. A refund or a family-sharing
 * removal means the money is gone, so the time is gone with it - checking only
 * expiry let somebody buy a year, claim a refund, press Restore and keep the
 * year. Apple stamps the revocation into the transaction, so the restore
 * carries the evidence against itself.
 */
export function entitlementIsLive(tx: AppleTransaction, now = new Date()): boolean {
  if (tx.revokedAt) return false;
  if (!tx.expiresAt) return true; // non-expiring product
  return tx.expiresAt.getTime() > now.getTime();
}

/** An App Store Server Notification, verified. */
export interface AppleNotification {
  /** e.g. DID_RENEW, EXPIRED, REFUND. Apple adds new ones without notice. */
  type: string;
  subtype: string | null;
  /** Apple's id for this delivery. The same event is retried under the same id. */
  uuid: string | null;
  /**
   * The subscription the event is about.
   *
   * Null for the notifications that carry no transaction at all - TEST, which
   * is what the "Send Test Notification" button in App Store Connect produces,
   * and the external-purchase and consumption families.
   */
  transaction: AppleTransaction | null;
  /**
   * How long Apple will keep retrying a failed payment while still counting
   * the person as a subscriber, if the billing grace period is switched on.
   *
   * Needed because it is the one case where the transaction alone gives the
   * wrong answer: on DID_FAIL_TO_RENEW the transaction has already expired,
   * but Apple is still trying the card and still treats them as entitled.
   * Reading only the expiry would cut off somebody mid-grace who is about to
   * pay, which is both unkind and pointless.
   */
  gracePeriodExpiresAt: Date | null;
}

/**
 * Verify an App Store Server Notification V2 and return what it says.
 *
 * This is the half of the purchase loop the device cannot do. A renewal
 * happens a month after anybody last opened the app, and a refund happens
 * somewhere else entirely: without this the server's idea of who is paying
 * only ever updates when the payer themselves launches the app, so a renewed
 * subscriber reads as free until they do, and a refunded one reads as paid for
 * ever.
 *
 * Verified exactly like a transaction, against the same Apple roots, and for
 * the same reason: the request arrives from the open internet with no
 * authentication of any kind. Anybody can POST to this endpoint. The signature
 * is the only thing that makes it Apple's.
 *
 * Notably NOT needed here: the .p8 App Store Server API key. That is for
 * asking Apple questions; this is Apple telling us, already signed.
 */
export async function verifySignedNotification(
  signedPayload: string,
): Promise<AppleNotification> {
  if (!signedPayload || signedPayload.split('.').length !== 3) {
    throw new AppleVerificationError('not a signed notification');
  }

  let payload: ResponseBodyV2DecodedPayload | null = null;
  let verifier: SignedDataVerifier | null = null;
  let lastError: unknown = null;

  // Same environment sweep as a transaction, for the same reason: nothing
  // outside the signature says whether this came from Sandbox or Production,
  // and a TestFlight build produces Sandbox notifications from the very same
  // binary that produces Production ones once it ships.
  for (const env of allowedEnvironments()) {
    try {
      const v = verifierFor(env);
      payload = await v.verifyAndDecodeNotification(signedPayload);
      verifier = v;
      break;
    } catch (err) {
      lastError = err;
    }
  }

  if (!payload || !verifier) {
    throw new AppleVerificationError(
      `notification did not verify: ${lastError instanceof Error ? lastError.message : lastError}`,
    );
  }

  // The transaction is a second signed document nested inside the first, and
  // it is the one that carries the product, the expiry and any revocation. The
  // outer envelope only says what kind of event this is.
  const signedTx = payload.data?.signedTransactionInfo;
  const transaction = signedTx
    ? toAppleTransaction(await verifier.verifyAndDecodeTransaction(signedTx))
    : null;

  const signedRenewal = payload.data?.signedRenewalInfo;
  const renewal = signedRenewal
    ? await verifier.verifyAndDecodeRenewalInfo(signedRenewal)
    : null;

  return {
    type: String(payload.notificationType ?? ''),
    subtype: payload.subtype ? String(payload.subtype) : null,
    uuid: payload.notificationUUID ?? null,
    transaction,
    gracePeriodExpiresAt: renewal?.gracePeriodExpiresDate
      ? new Date(renewal.gracePeriodExpiresDate)
      : null,
  };
}

/**
 * Whether a notification leaves the person entitled, right now.
 *
 * Deliberately derived from the signed documents rather than from
 * [AppleNotification.type]. Apple adds notification types without warning, and
 * a switch over them is a list of the ones that existed when it was written:
 * the first unhandled type silently becomes "no change". The transaction, on
 * the other hand, always says the same three things - what was bought, when it
 * runs out, and whether the money was taken back - and those are the whole
 * answer for every event that matters.
 */
export function notificationLeavesEntitlement(
  note: AppleNotification,
  now = new Date(),
): boolean {
  const tx = note.transaction;
  if (!tx) return false;
  // Revocation beats everything, including an unexpired grace period: there is
  // no grace on a refund.
  if (tx.revokedAt) return false;
  if (entitlementIsLive(tx, now)) return true;
  const grace = note.gracePeriodExpiresAt;
  return grace !== null && grace.getTime() > now.getTime();
}
