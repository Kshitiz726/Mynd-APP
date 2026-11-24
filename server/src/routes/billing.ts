import { Router, type Request, type Response } from 'express';
import type Stripe from 'stripe';
import { config } from '../config.js';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import {
  stripe,
  planCatalog,
  planForAppleProduct,
  billingStore,
  isPremium,
  applyStripeSubscription,
  type SubRecord,
} from '../services/billing.js';
import {
  AppleVerificationError,
  entitlementIsLive,
  verifySignedTransaction,
} from '../services/apple.js';

export const billingRouter = Router();

// Absolute base the hosted Stripe page redirects the *browser* back to. This is
// not the host the app calls us on: the emulator's Chrome can't reach the
// 10.0.2.2 host-loopback alias when a VPN/DNS blocker is active, so we pin
// PUBLIC_BASE_URL=http://localhost:8080 in dev (with `adb reverse tcp:8080
// tcp:8080`) and the real https origin in prod. Falls back to the request host.
function baseUrl(req: Request): string {
  return process.env.PUBLIC_BASE_URL || `${req.protocol}://${req.get('host')}`;
}

function statusPayload(rec: SubRecord) {
  return {
    premium: isPremium(rec),
    tier: rec.tier,
    status: rec.status,
    interval: rec.interval,
    currentPeriodEnd: rec.currentPeriodEnd,
  };
}

// ── Catalogue ────────────────────────────────────────────────────────────────
// The app renders whatever this returns, so pricing/plan structure lives in one
// place (Stripe + env) rather than being hard-coded twice.
billingRouter.get('/billing/plans', requireAuth, async (_req, res) => {
  if (!stripe) return res.status(503).json({ error: 'billing not configured' });
  const plans = await Promise.all(
    planCatalog().map(async (p) => {
      try {
        const price = await stripe!.prices.retrieve(p.priceId);
        return {
          id: p.id,
          tier: p.tier,
          interval: p.interval,
          amount: price.unit_amount, // minor units (pence)
          currency: price.currency, // e.g. 'gbp'
        };
      } catch {
        return { id: p.id, tier: p.tier, interval: p.interval, amount: null, currency: null };
      }
    }),
  );
  res.json({ publishableKey: config.stripe.publishableKey, plans });
});

// ── Where does this user stand ──────────────────────────────────────────────
billingRouter.get('/billing/status', requireAuth, async (req, res) => {
  const rec = await billingStore.get(req.user.id);
  res.json(statusPayload(rec));
});

// ── Apple: record a verified StoreKit purchase ──────────────────────────────
//
// The app sends the signed transaction StoreKit gave it. Everything that
// decides entitlement is read out of Apple's signature, never out of the
// request body: the client sends a productId and a planId too, but those are
// only used to notice a mismatch, never to grant anything. A client that could
// name its own tier would not need to pay for one.
billingRouter.post('/billing/apple/verify', requireAuth, async (req, res) => {
  const receipt = typeof req.body?.receipt === 'string' ? req.body.receipt : '';

  let tx;
  try {
    tx = await verifySignedTransaction(receipt);
  } catch (err) {
    if (err instanceof AppleVerificationError) {
      console.warn('[billing] apple receipt rejected:', err.message);
      return res.status(400).json({ error: 'receipt did not verify', code: 'apple_invalid_receipt' });
    }
    throw err;
  }

  // Apple's product id decides the plan. Whatever planId the client claimed is
  // never read: a client that could name its own tier would not need to buy
  // one.
  const plan = planForAppleProduct(tx.productId);
  if (!plan) {
    console.warn('[billing] verified apple transaction for an unknown product:', tx.productId);
    return res.status(400).json({ error: 'unknown product', code: 'apple_unknown_product' });
  }

  // One Apple subscription, one account.
  //
  // Without this, restoring on a second account is a free second subscription,
  // and it is the first thing anybody tries. Checked before anything is
  // granted so the app can say why, rather than surfacing a unique-constraint
  // failure from the insert.
  const owner = await billingStore.userForAppleTransaction(tx.originalTransactionId);
  if (owner && owner !== req.user.id) {
    return res.status(409).json({
      error: 'this subscription is already active on another OurMynd account',
      code: 'apple_already_claimed',
    });
  }

  const live = entitlementIsLive(tx);
  const rec = await billingStore.upsert(req.user.id, {
    tier: live ? plan.tier : 'free',
    // Apple has no 'past_due': a lapsed subscription simply stops. Mapping it
    // to canceled keeps isPremium's existing rules working unchanged.
    status: live ? 'active' : 'canceled',
    interval: plan.interval,
    currentPeriodEnd: tx.expiresAt ? tx.expiresAt.toISOString() : null,
    appleOriginalTransactionId: tx.originalTransactionId,
    appleProductId: tx.productId,
  });

  res.json(statusPayload(rec));
});

// ── Start a subscription ────────────────────────────────────────────────────
// Creates (or reuses) the Stripe customer for this user and opens a hosted
// Checkout Session for the chosen price. The app launches the returned url in
// the system browser and, on return, calls /billing/confirm with the sessionId.
billingRouter.post('/billing/checkout', requireAuth, async (req, res) => {
  if (!stripe) return res.status(503).json({ error: 'billing not configured' });
  // The app sends a catalogue id ('pro_year'); we resolve the real Stripe price
  // id here so price ids never have to live in the client. A raw priceId is also
  // accepted for flexibility.
  const planId = String(req.body?.planId ?? '');
  const priceIdRaw = String(req.body?.priceId ?? '');
  const entry = planCatalog().find((p) => p.id === planId || p.priceId === priceIdRaw);
  if (!entry) {
    return res.status(400).json({ error: 'unknown plan' });
  }
  const priceId = entry.priceId;

  try {
    const rec = await billingStore.get(req.user.id);
    let customerId = rec.stripeCustomerId;
    if (!customerId) {
      const customer = await stripe.customers.create({
        metadata: { userId: req.user.id, handle: req.user.handle },
        name: req.user.displayName,
      });
      customerId = customer.id;
      await billingStore.upsert(req.user.id, { stripeCustomerId: customerId });
    }

    const base = baseUrl(req);
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      customer: customerId,
      line_items: [{ price: priceId, quantity: 1 }],
      client_reference_id: req.user.id,
      subscription_data: { metadata: { userId: req.user.id } },
      metadata: { userId: req.user.id },
      success_url: `${base}/api/billing/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${base}/api/billing/cancel`,
      allow_promotion_codes: true,
      // This Stripe account has Managed Payments on by default, which demands a
      // product tax code we don't set. Opt the session out so a plain
      // subscription checkout goes through. (Not yet in the SDK types.)
      managed_payments: { enabled: false },
    } as any);

    res.json({ url: session.url, sessionId: session.id });
  } catch (e: any) {
    console.error('[billing] checkout failed:', e?.message ?? e);
    res.status(502).json({ error: 'could not start checkout' });
  }
});

// ── Manage an existing subscription (update / cancel) ───────────────────────
// Opens Stripe's hosted Billing Portal for this customer, where they can switch
// plan, update card, or cancel. Same pattern as checkout: we return a URL the
// app launches in the browser, and reconcile entitlement on resume.
billingRouter.post('/billing/portal', requireAuth, async (req, res) => {
  if (!stripe) return res.status(503).json({ error: 'billing not configured' });
  try {
    const rec = await billingStore.get(req.user.id);
    if (!rec.stripeCustomerId) {
      return res.status(409).json({ error: 'no subscription to manage' });
    }
    const base = baseUrl(req);
    const portal = await stripe.billingPortal.sessions.create({
      customer: rec.stripeCustomerId,
      return_url: `${base}/api/billing/success`,
    });
    res.json({ url: portal.url });
  } catch (e: any) {
    console.error('[billing] portal failed:', e?.message ?? e);
    res.status(502).json({ error: 'could not open billing portal' });
  }
});

// ── Reconcile on return ─────────────────────────────────────────────────────
// The app calls this when it comes back to the foreground after checkout. We
// pull the session straight from Stripe; if it is paid we fold its subscription
// into our store so entitlement flips on without needing a webhook in dev.
billingRouter.post('/billing/confirm', requireAuth, async (req, res) => {
  if (!stripe) return res.status(503).json({ error: 'billing not configured' });
  const sessionId = String(req.body?.sessionId ?? '');
  if (!sessionId) return res.status(400).json({ error: 'missing sessionId' });

  try {
    const session = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ['subscription'],
    });
    // Guard: the session must belong to the caller.
    //
    // Fails closed. This used to be `if (client_reference_id && ...)`, which
    // skipped the check entirely whenever the field was absent - so a session
    // created without one could be claimed by any authenticated caller who
    // knew its id. Checkout always stamps it, so a missing value means
    // something we did not create, and the answer to that is no.
    if (session.client_reference_id !== req.user.id) {
      return res.status(403).json({ error: 'session does not belong to you' });
    }
    if (session.payment_status === 'paid' && session.subscription) {
      const sub =
        typeof session.subscription === 'string'
          ? await stripe.subscriptions.retrieve(session.subscription)
          : (session.subscription as Stripe.Subscription);
      const rec = await applyStripeSubscription(req.user.id, sub);
      return res.json(statusPayload(rec));
    }
    // Not paid yet (user backed out, or async payment pending).
    const rec = await billingStore.get(req.user.id);
    res.json(statusPayload(rec));
  } catch (e: any) {
    console.error('[billing] confirm failed:', e?.message ?? e);
    res.status(502).json({ error: 'could not confirm checkout' });
  }
});

// ── Hosted return pages (shown in the browser, not the app) ─────────────────
const returnPage = (title: string, body: string) => `<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title><style>
  body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#F4F1FB;color:#1c1330;
    display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;padding:24px}
  .card{background:#fff;border-radius:22px;padding:36px 28px;max-width:340px;text-align:center;
    box-shadow:0 18px 50px rgba(99,102,241,.18)}
  h1{font-size:22px;margin:0 0 8px} p{color:#5b5470;font-size:14px;line-height:1.5;margin:0}
  .dot{width:56px;height:56px;border-radius:50%;background:linear-gradient(135deg,#8b7ff0,#6366F1);
    margin:0 auto 18px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:28px}
</style></head><body><div class="card">${body}</div></body></html>`;

billingRouter.get('/billing/success', (_req, res) => {
  res.type('html').send(
    returnPage(
      'Payment complete',
      `<div class="dot">✓</div><h1>You're all set</h1>
       <p>Your OurMynd subscription is active. Head back to the app - it'll unlock your plan in a moment.</p>`,
    ),
  );
});

billingRouter.get('/billing/cancel', (_req, res) => {
  res.type('html').send(
    returnPage(
      'Checkout cancelled',
      `<div class="dot" style="background:linear-gradient(135deg,#c0b9d6,#8b84a3)">–</div>
       <h1>No charge made</h1><p>You closed checkout before finishing. Return to the app to try again anytime.</p>`,
    ),
  );
});

// ── Webhook (prod entitlement source of truth) ──────────────────────────────
// Mounted separately in server.ts with a raw body so the signature verifies.
// In dev without a webhook secret we skip verification and simply ignore events
// (the confirm-poll above is authoritative there).
export async function billingWebhookHandler(req: Request, res: Response) {
  if (!stripe) return res.status(503).end();
  let event: Stripe.Event;
  if (config.stripe.webhookSecret) {
    try {
      event = stripe.webhooks.constructEvent(
        req.body as Buffer,
        req.headers['stripe-signature'] as string,
        config.stripe.webhookSecret,
      );
    } catch (e: any) {
      console.error('[billing] bad webhook signature:', e?.message ?? e);
      return res.status(400).send(`Webhook Error: ${e?.message}`);
    }
  } else if (config.isProd) {
    // Unsigned events are never acceptable in production.
    //
    // This branch used to parse them anyway, guarded only by a comment saying
    // "dev only" and by nothing at all in code. Deployed with the secret unset,
    // it meant any unauthenticated caller could POST a subscription event and
    // grant themselves premium: an entitlement endpoint with no authentication
    // in front of it. Refusing outright is the only safe reading, and a 500 is
    // honest - this is our misconfiguration, not a malformed request, and it
    // makes the failure loud in the Stripe dashboard rather than silent.
    console.error('[billing] STRIPE_WEBHOOK_SECRET is not set - refusing unsigned webhook');
    return res.status(500).json({ error: 'webhook verification not configured' });
  } else {
    // Local development only, and only ever reachable when NODE_ENV !== production.
    try {
      event = JSON.parse((req.body as Buffer).toString('utf8')) as Stripe.Event;
    } catch {
      return res.status(400).end();
    }
  }

  // Idempotency. Stripe retries on any non-2xx and may deliver the same event
  // more than once even on success, so applying an event twice has to be a
  // no-op rather than a second upgrade or a double-counted cancellation. The
  // insert is the lock: a duplicate id violates the primary key, and losing
  // that race means somebody else is already handling this event.
  if (config.hasDb && event.id) {
    try {
      const fresh = await db.oneOrNone(
        `insert into billing_events (id, type) values ($1, $2)
         on conflict (id) do nothing
         returning id`,
        [event.id, event.type],
      );
      if (!fresh) {
        return res.json({ received: true, duplicate: true });
      }
    } catch (e: any) {
      console.error('[billing] idempotency check failed:', e?.message ?? e);
      // Fall through and process. Refusing here would let a transient database
      // error drop a real payment event permanently, which is worse than the
      // rare double-apply this is guarding against.
    }
  }

  try {
    switch (event.type) {
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const userId =
          (sub.metadata?.userId as string | undefined) ??
          (await billingStore.userForCustomer(
            typeof sub.customer === 'string' ? sub.customer : sub.customer.id,
          ));
        if (userId) await applyStripeSubscription(userId, sub);
        break;
      }

      // Money going back out has to take the entitlement with it. Without
      // these, a refunded or disputed payment left the account premium
      // indefinitely: the subscription events never fire for a chargeback, so
      // nothing else would ever revoke it.
      case 'charge.refunded':
      case 'charge.dispute.created': {
        const charge = event.data.object as Stripe.Charge;
        const customerId =
          typeof charge.customer === 'string' ? charge.customer : charge.customer?.id;
        if (customerId) {
          const userId = await billingStore.userForCustomer(customerId);
          if (userId) {
            console.warn('[billing] revoking entitlement after', event.type, { customerId });
            await billingStore.clear(userId);
          }
        }
        break;
      }
      default:
        break;
    }
  } catch (e: any) {
    console.error('[billing] webhook handler error:', e?.message ?? e);
  }
  res.json({ received: true });
}
