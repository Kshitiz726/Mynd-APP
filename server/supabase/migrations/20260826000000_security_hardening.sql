-- OurMynd: security hardening.
--
-- Run: psql "$DATABASE_URL" -f supabase/migrations/20260826000000_security_hardening.sql
--   or: npm run migrate
--
-- Three things, all closing findings from the 25 Aug security review:
--   1. Webhook idempotency, so a replayed Stripe event cannot apply twice.
--   2. Token revocation, so signing out or deleting an account actually ends
--      the session rather than only forgetting it on one device.
--   3. Row level security on every table holding user data.

-- ============ 1. WEBHOOK IDEMPOTENCY ============
-- Stripe retries on any non-2xx and may redeliver even after a success, so
-- "apply this event" has to be safe to call twice. The primary key is the lock:
-- the first delivery inserts and processes, every later one conflicts and is
-- acknowledged without touching entitlement.
create table if not exists billing_events (
  id           text primary key,     -- Stripe's evt_… id
  type         text not null,
  received_at  timestamptz not null default now()
);

-- Stripe only guarantees replay within a bounded window, so this table is a
-- short-horizon ledger rather than permanent history. Prune anything older
-- than 30 days on each migration run; it never needs to grow without bound.
delete from billing_events where received_at < now() - interval '30 days';

-- ============ 2. TOKEN REVOCATION ============
-- Sessions were 30-day bearer JWTs with no way to end one early: signing out
-- cleared the phone's copy and nothing else, so a token captured from a backup
-- or a rooted device stayed valid for the rest of its month.
--
-- A counter rather than a deny-list. Every issued token carries the value of
-- this column at the time it was minted; bumping the column invalidates every
-- token already out there in one statement, with no per-token bookkeeping and
-- nothing to expire. Sign-out, account deletion and any future "sign out
-- everywhere" all reduce to `set token_version = token_version + 1`.
alter table users add column if not exists token_version integer not null default 0;

-- ============ 3. ROW LEVEL SECURITY ============
-- The API server connects as the table owner and scopes every query to the
-- authenticated user in application code, so this is defence in depth rather
-- than the primary control. It matters because it is the control that still
-- holds if someone later points PostgREST, the Supabase client, or an
-- analytics tool at this database: without RLS, any such connection would read
-- every row of every user.
--
-- `force row level security` as well as `enable`: enable alone exempts the
-- table owner, which is precisely the role the API connects as, so the policies
-- would have been decorative.
do $$
declare t text;
begin
  foreach t in array array[
    'users', 'posts', 'post_tags', 'reactions', 'user_state',
    'health_consent_events', 'subscriptions', 'notes'
  ] loop
    if to_regclass(t) is not null then
      execute format('alter table %I enable row level security', t);
      execute format('alter table %I force row level security', t);
    end if;
  end loop;
end $$;

-- The API server's own role must keep full access, or every request breaks.
-- It is named explicitly so that *only* it bypasses the policies below, and
-- any other role reaching this database is subject to them.
do $$
declare t text; owner_role text := current_user;
begin
  foreach t in array array[
    'users', 'posts', 'post_tags', 'reactions', 'user_state',
    'health_consent_events', 'subscriptions', 'notes'
  ] loop
    if to_regclass(t) is not null then
      execute format('drop policy if exists api_server_full_access on %I', t);
      execute format(
        'create policy api_server_full_access on %I to %I using (true) with check (true)',
        t, owner_role);
    end if;
  end loop;
end $$;

-- Owner-only policies for any *other* role (a Supabase anon/authenticated
-- client, a BI tool). These read auth.uid() where Supabase provides it and
-- deny everything where it does not, which is the safe default.
do $$
begin
  if to_regclass('user_state') is not null
     and exists (select 1 from pg_proc where proname = 'uid'
                  and pronamespace = (select oid from pg_namespace where nspname = 'auth')) then
    drop policy if exists own_rows on user_state;
    create policy own_rows on user_state
      using (user_id = auth.uid()) with check (user_id = auth.uid());

    drop policy if exists own_rows on health_consent_events;
    create policy own_rows on health_consent_events
      using (user_id = auth.uid()) with check (user_id = auth.uid());

    drop policy if exists own_rows on subscriptions;
    create policy own_rows on subscriptions
      using (user_id = auth.uid()) with check (user_id = auth.uid());
  end if;
end $$;

-- ============ 4. SERVER-SIDE COACH USAGE ============
-- The free-tier message cap lived in the phone's SharedPreferences, so it was
-- a suggestion: clearing app data reset it, and the server never saw a coach
-- message at all because the app called the model provider directly. Now that
-- every turn is proxied (see src/routes/coach.ts), the count lives here.
--
-- Keyed by local day rather than a rolling window: "five a day" is what the
-- paywall promises, and a window would reset at a time nobody can predict.
create table if not exists coach_usage (
  user_id uuid not null references users(id) on delete cascade,
  day     date not null,
  count   integer not null default 0,
  primary key (user_id, day)
);

-- Only ever read for today, and only for one user.
create index if not exists coach_usage_day_idx on coach_usage (day);

-- Old buckets are of no interest once the day has passed.
delete from coach_usage where day < current_date - 90;
