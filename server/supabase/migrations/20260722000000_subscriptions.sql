-- Billing: one subscription row per user, kept in sync with Stripe.
--
-- We store only what the app needs to gate features and render the plan card:
-- the tier (plus/pro), the billing interval, whether it is currently active,
-- when the paid period ends, and the Stripe ids we need to reconcile. The card
-- number and everything sensitive stays with Stripe - we never see it.

do $$ begin
  create type subscription_tier   as enum ('free','plus','pro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type subscription_status as enum ('active','trialing','past_due','canceled','incomplete');
exception when duplicate_object then null; end $$;

create table if not exists subscriptions (
  user_id                uuid primary key references users(id) on delete cascade,
  tier                   subscription_tier   not null default 'free',
  status                 subscription_status not null default 'canceled',
  interval               text,                       -- 'month' | 'year' | null
  stripe_customer_id     text,
  stripe_subscription_id text,
  price_id               text,
  current_period_end     timestamptz,
  updated_at             timestamptz not null default now()
);

-- Look up a subscription by the Stripe customer when a webhook arrives.
create index if not exists subscriptions_customer_idx on subscriptions (stripe_customer_id);
