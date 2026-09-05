-- OurMynd: separate, evidenced consent for health-related data.
--
-- Run: psql "$DATABASE_URL" -f supabase/migrations/20260825000000_health_consent.sql
--   or: npm run migrate
--
-- The published privacy policy promises four things about this consent, and
-- each one is a constraint on the shape below:
--
--   1. It is asked for on its own screen, not bundled into the Terms. So it
--      cannot be a flag set by the sign-up path - it needs its own decision
--      record, written by its own endpoint.
--   2. It is not a condition of having an account. So "declined" has to be a
--      real, storable answer rather than the absence of one: we must be able
--      to tell someone who said no from someone who has not been asked, or the
--      app would nag the first group forever.
--   3. It can be withdrawn at any time. So the state changes over the life of
--      the account, and the current value alone cannot answer "what were they
--      consenting to, and when".
--   4. It has to be evidenced later. So every transition is kept, with the
--      version of the policy that was on screen at the time.
--
-- Hence two things rather than one: an append-only log of decisions (the
-- evidence), and the current state denormalised onto users (the gate). The
-- log is the source of truth; the columns are a cache of its latest row so
-- that gating a request costs no join.

-- ============ CURRENT STATE (the gate) ============
-- Three-valued on purpose: null = never asked, false = declined, true = given.
-- A plain `not null default false` would have erased the difference between
-- "said no" and "not asked yet", which is exactly the distinction promise 2
-- rests on.
alter table users add column if not exists health_consent_granted boolean;

-- When they last answered, whichever way they answered. Drives the "you
-- declined on 3 August" line in Settings as well as the granted case.
alter table users add column if not exists health_consent_decided_at timestamptz;

-- The policy version that was on screen when they answered. Consent to a
-- document is consent to *that* document; when the policy changes materially
-- this is what tells us whose consent is now stale and has to be re-asked.
alter table users add column if not exists health_consent_version text;

-- ============ THE EVIDENCE (append-only) ============
create table if not exists health_consent_events (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  -- true = given, false = withdrawn/declined.
  granted        boolean not null,
  policy_version text not null,
  -- Where the decision was taken: 'onboarding' or 'settings'. Kept because
  -- promise 1 is specifically about *where* consent was collected, and an
  -- audit that cannot show that cannot evidence it.
  source         text not null,
  occurred_at    timestamptz not null default now()
);

-- The audit read is always "this user's decisions, newest first".
create index if not exists health_consent_events_user_idx
  on health_consent_events (user_id, occurred_at desc);

-- Deliberately no update/delete path in the app for this table. Rows are only
-- removed when the account is, by the cascade above - an audit trail that the
-- audited party can edit is not an audit trail.
