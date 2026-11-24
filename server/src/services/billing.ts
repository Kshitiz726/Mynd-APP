import Stripe from 'stripe';
import { config } from '../config.js';
import { db } from '../db.js';

// One Stripe client for the process. Null when no secret key is configured, so
// the routes can answer a clean 503 instead of throwing on boot.
// Bounded and retried.
//
// The SDK defaults to no timeout, so a slow Stripe call could pin a request
// (and its database connection) open for as long as the socket stayed up.
// Two retries because checkout and webhook handling are worth one more attempt
// before failing a paying customer.
export const stripe = config.hasStripe
  ? new Stripe(config.stripe.secretKey, { timeout: 10_000, maxNetworkRetries: 2 })
  : null;

export type Tier = 'free' | 'plus' | 'pro';
export type Interval = 'month' | 'year';

export interface PlanEntry {
  id: string; // e.g. 'plus_month'
  tier: Exclude<Tier, 'free'>;
  interval: Interval;
  priceId: string;
}

/**
 * Every plan this server has ever sold, including ones it no longer offers.
 *
 * Separate from the sellable catalogue on purpose. Plus was withdrawn because
 * Pro's only distinct benefit over it was "everything in Plus", which unlocks
 * nothing and which Apple rejects as an in-app purchase. But a withdrawn plan
 * is not a plan nobody holds: anybody already on Plus still renews, and their
 * renewal arrives as a webhook carrying the Plus price id. Resolving that
 * through the sellable list alone would find no match, fall through to
 * 'free', and cancel a paying subscriber's entitlement on the very event that
 * confirms they have paid again.
 */
function allKnownPlans(): PlanEntry[] {
  const p = config.stripe.prices;
  const entries: PlanEntry[] = [
    { id: 'pro_month', tier: 'pro', interval: 'month', priceId: p.proMonthly },
    { id: 'pro_year', tier: 'pro', interval: 'year', priceId: p.proYearly },
    // Withdrawn. Honoured, never offered.
    { id: 'plus_month', tier: 'plus', interval: 'month', priceId: p.plusMonthly },
    { id: 'plus_year', tier: 'plus', interval: 'year', priceId: p.plusYearly },
  ];
  return entries.filter((e) => e.priceId);
}

/** Plans a new subscriber may actually buy. What the client is shown. */
export function planCatalog(): PlanEntry[] {
  return allKnownPlans().filter((e) => e.tier === 'pro');
}

/**
 * Apple's product ids, and what each one entitles the holder to.
 *
 * Deliberately independent of [allKnownPlans]. That list is filtered by which
 * Stripe price ids are configured, which is right for a Stripe catalogue and
 * wrong for Apple: an App Store purchase has to resolve on a server with no
 * Stripe keys at all, and routing it through the Stripe list would have made
 * every iOS subscription fail to verify the moment STRIPE_PRICE_PRO_MONTHLY
 * was unset. Apple's ids are fixed and permanent, so they are simply written
 * down.
 *
 * These strings must match IapProducts in the app and App Store Connect
 * exactly; a product id can never be edited or reused there.
 */
const APPLE_PRODUCTS: Record<string, { id: string; tier: Exclude<Tier, 'free'>; interval: Interval }> = {
  'com.ourmynd.app.pro.monthly': { id: 'pro_month', tier: 'pro', interval: 'month' },
  'com.ourmynd.app.pro.yearly': { id: 'pro_year', tier: 'pro', interval: 'year' },
};

/** What an Apple product id entitles the holder to, or null if we do not sell it. */
export function planForAppleProduct(
  productId: string,
): { id: string; tier: Exclude<Tier, 'free'>; interval: Interval } | null {
  return APPLE_PRODUCTS[productId] ?? null;
}

/** Map a Stripe price id back to the tier/interval it represents. */
export function planForPrice(priceId: string): { tier: Tier; interval: Interval | null } {
  // Against every plan, not just the sellable ones - see allKnownPlans.
  const hit = allKnownPlans().find((e) => e.priceId === priceId);
  return hit ? { tier: hit.tier, interval: hit.interval } : { tier: 'free', interval: null };
}

export interface SubRecord {
  tier: Tier;
  status: string; // active | trialing | past_due | canceled | incomplete
  interval: Interval | null;
  stripeCustomerId: string | null;
  stripeSubscriptionId: string | null;
  priceId: string | null;
  currentPeriodEnd: string | null; // ISO

  /**
   * Apple's identity for the subscription, stable across every renewal,
   * upgrade and restore. Non-null means Apple owns this one: we cannot cancel
   * or change it, and the cancellation route to offer is Apple's, not ours.
   */
  appleOriginalTransactionId: string | null;
  appleProductId: string | null;
}

const FREE: SubRecord = {
  tier: 'free',
  status: 'canceled',
  interval: null,
  stripeCustomerId: null,
  stripeSubscriptionId: null,
  priceId: null,
  currentPeriodEnd: null,
  appleOriginalTransactionId: null,
  appleProductId: null,
};

// In dev without a DB (embedded-postgres off) we still want the flow to be
// exercisable, so the store falls back to a per-process map keyed by user id.
const memStore = new Map<string, SubRecord>();

/** True when the subscription entitles the user to premium features. */
export function isPremium(rec: SubRecord): boolean {
  if (rec.tier === 'free') return false;
  if (rec.status !== 'active' && rec.status !== 'trialing') return false;
  if (rec.currentPeriodEnd && new Date(rec.currentPeriodEnd).getTime() < Date.now()) return false;
  return true;
}

export const billingStore = {
  async get(userId: string): Promise<SubRecord> {
    if (!config.hasDb) return memStore.get(userId) ?? { ...FREE };
    const row = await db.oneOrNone(
      `select tier, status, interval, stripe_customer_id, stripe_subscription_id,
              price_id, current_period_end,
              apple_original_transaction_id, apple_product_id
         from subscriptions where user_id = $1`,
      [userId],
    );
    if (!row) return { ...FREE };
    return {
      tier: row.tier,
      status: row.status,
      interval: row.interval,
      stripeCustomerId: row.stripe_customer_id,
      stripeSubscriptionId: row.stripe_subscription_id,
      priceId: row.price_id,
      currentPeriodEnd: row.current_period_end ? new Date(row.current_period_end).toISOString() : null,
      appleOriginalTransactionId: row.apple_original_transaction_id ?? null,
      appleProductId: row.apple_product_id ?? null,
    };
  },

  async upsert(userId: string, patch: Partial<SubRecord>): Promise<SubRecord> {
    const current = await this.get(userId);
    const next: SubRecord = { ...current, ...patch };
    if (!config.hasDb) {
      memStore.set(userId, next);
      return next;
    }
    await db.none(
      `insert into subscriptions
         (user_id, tier, status, interval, stripe_customer_id, stripe_subscription_id,
          price_id, current_period_end, apple_original_transaction_id,
          apple_product_id, updated_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, now())
       on conflict (user_id) do update set
         tier = excluded.tier,
         status = excluded.status,
         interval = excluded.interval,
         stripe_customer_id = excluded.stripe_customer_id,
         stripe_subscription_id = excluded.stripe_subscription_id,
         price_id = excluded.price_id,
         current_period_end = excluded.current_period_end,
         apple_original_transaction_id = excluded.apple_original_transaction_id,
         apple_product_id = excluded.apple_product_id,
         updated_at = now()`,
      [
        userId,
        next.tier,
        next.status,
        next.interval,
        next.stripeCustomerId,
        next.stripeSubscriptionId,
        next.priceId,
        next.currentPeriodEnd,
        next.appleOriginalTransactionId,
        next.appleProductId,
      ],
    );
    return next;
  },

  /**
   * Drop the account back to free, keeping the Stripe ids.
   *
   * Used when money is reversed - a refund or a dispute - where there may be no
   * subscription event to follow. The customer id is deliberately retained so a
   * later legitimate purchase still reconciles to the same Stripe customer
   * rather than creating a second one.
   */
  async clear(userId: string): Promise<SubRecord> {
    return this.upsert(userId, {
      tier: 'free',
      status: 'canceled',
      interval: null,
      stripeSubscriptionId: null,
      priceId: null,
      currentPeriodEnd: null,
    });
  },

  /**
   * Who already owns this Apple subscription, if anybody.
   *
   * The guard against one paid Apple ID entitling several accounts. Restoring
   * on a second account is the ordinary way that happens and it is the first
   * thing anybody tries, so it is checked before anything is granted rather
   * than left to the unique index to reject afterwards - the index protects
   * the data, this produces an answer the app can explain.
   */
  async userForAppleTransaction(originalTransactionId: string): Promise<string | null> {
    if (!config.hasDb) {
      for (const [uid, rec] of memStore) {
        if (rec.appleOriginalTransactionId === originalTransactionId) return uid;
      }
      return null;
    }
    const row = await db.oneOrNone(
      `select user_id from subscriptions
        where apple_original_transaction_id = $1 limit 1`,
      [originalTransactionId],
    );
    return row?.user_id ?? null;
  },

  /** Find the user id we stamped on a Stripe customer, for webhook reconciliation. */
  async userForCustomer(customerId: string): Promise<string | null> {
    if (!config.hasDb) {
      for (const [uid, rec] of memStore) if (rec.stripeCustomerId === customerId) return uid;
      return null;
    }
    const row = await db.oneOrNone(
      `select user_id from subscriptions where stripe_customer_id = $1 limit 1`,
      [customerId],
    );
    return row?.user_id ?? null;
  },
};

/**
 * Fold a Stripe Subscription object into our store for [userId]. Called from
 * both the return-poll (confirm) and the webhook, so entitlement is identical
 * whichever path fires first.
 */
export async function applyStripeSubscription(
  userId: string,
  sub: Stripe.Subscription,
): Promise<SubRecord> {
  const priceId = sub.items.data[0]?.price?.id ?? null;
  const { tier, interval } = priceId ? planForPrice(priceId) : { tier: 'free' as Tier, interval: null };
  const periodEnd = sub.current_period_end ? new Date(sub.current_period_end * 1000).toISOString() : null;
  return billingStore.upsert(userId, {
    tier: sub.status === 'canceled' ? 'free' : tier,
    status: sub.status,
    interval,
    stripeCustomerId: typeof sub.customer === 'string' ? sub.customer : sub.customer.id,
    stripeSubscriptionId: sub.id,
    priceId,
    currentPeriodEnd: periodEnd,
  });
}
