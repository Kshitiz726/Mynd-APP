-- Apple's side of a subscription.
--
-- The same `subscriptions` row serves both rails, because the rest of the
-- server only ever asks "what tier is this user on": splitting it in two would
-- mean every entitlement read had to know which store sold it, and a user who
-- bought on the web and later signs in on an iPhone is one subscriber, not
-- two.
--
-- What Apple gives us that Stripe does not is the original transaction id.
-- That, not the transaction id of a single payment, is the identity of the
-- subscription: every renewal, every upgrade and every restore carries a new
-- transaction id and the same original one. It is also what App Store Server
-- Notifications arrive keyed by, so without it a renewal notification has
-- nothing to match against.
alter table subscriptions
  add column if not exists apple_original_transaction_id text,
  add column if not exists apple_product_id              text;

-- One Apple subscription belongs to one account.
--
-- Unique rather than a plain index on purpose. The same Apple ID signing in to
-- two OurMynd accounts and restoring on both is the ordinary way one paid
-- subscription becomes two free rides, and it is not hypothetical - it is the
-- first thing anybody tries. The insert that would have created the second
-- one fails here instead, at the only layer that can see both rows.
create unique index if not exists subscriptions_apple_original_txn_idx
  on subscriptions (apple_original_transaction_id)
  where apple_original_transaction_id is not null;

-- Which store sold it, so the right cancellation route can be offered.
--
-- Derived rather than stored as a flag somebody has to remember to set: a row
-- with an Apple transaction was sold by Apple, and nothing else can be.
comment on column subscriptions.apple_original_transaction_id is
  'Apple''s originalTransactionId. Non-null means Apple owns this subscription: we cannot cancel or change it, and the user manages it in their Apple ID settings.';
