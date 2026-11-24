import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
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
