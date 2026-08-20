import Stripe from 'stripe';
import { config } from '../config.js';
import { db } from '../db.js';

// One Stripe client for the process. Null when no secret key is configured, so
// the routes can answer a clean 503 instead of throwing on boot.
export const stripe = config.hasStripe ? new Stripe(config.stripe.secretKey) : null;

export type Tier = 'free' | 'plus' | 'pro';
export type Interval = 'month' | 'year';

export interface PlanEntry {
  id: string; // e.g. 'plus_month'
  tier: Exclude<Tier, 'free'>;
  interval: Interval;
  priceId: string;
}

// The catalogue, built from whichever price ids are configured. The client asks
// for this so the app never hard-codes a Stripe price id of its own.
export function planCatalog(): PlanEntry[] {
  const p = config.stripe.prices;
  const entries: PlanEntry[] = [
    { id: 'plus_month', tier: 'plus', interval: 'month', priceId: p.plusMonthly },
    { id: 'plus_year', tier: 'plus', interval: 'year', priceId: p.plusYearly },
    { id: 'pro_month', tier: 'pro', interval: 'month', priceId: p.proMonthly },
    { id: 'pro_year', tier: 'pro', interval: 'year', priceId: p.proYearly },
  ];
  return entries.filter((e) => e.priceId);
}

/** Map a Stripe price id back to the tier/interval it represents. */
export function planForPrice(priceId: string): { tier: Tier; interval: Interval | null } {
  const hit = planCatalog().find((e) => e.priceId === priceId);
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
}

const FREE: SubRecord = {
  tier: 'free',
  status: 'canceled',
  interval: null,
  stripeCustomerId: null,
  stripeSubscriptionId: null,
  priceId: null,
  currentPeriodEnd: null,
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
              price_id, current_period_end
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
          price_id, current_period_end, updated_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8, now())
       on conflict (user_id) do update set
         tier = excluded.tier,
         status = excluded.status,
         interval = excluded.interval,
         stripe_customer_id = excluded.stripe_customer_id,
         stripe_subscription_id = excluded.stripe_subscription_id,
         price_id = excluded.price_id,
         current_period_end = excluded.current_period_end,
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
      ],
    );
    return next;
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
