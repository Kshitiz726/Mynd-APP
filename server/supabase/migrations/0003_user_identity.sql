-- OurMynd 0003: store the real Google identity (name + email) alongside the
-- anonymous public profile. These columns are NEVER shown in the UI — the app
-- keeps every user anonymous (display_name stays the generated handle). They
-- exist only for account recovery, support, and "restore everything on
-- re-login" (the account is keyed by email).
--
-- Run: psql "$DATABASE_URL" -f supabase/migrations/0003_user_identity.sql
--   or: npm run migrate

alter table users add column if not exists email     text;
alter table users add column if not exists full_name text;

-- Existing rows were created with handle = email, so backfill email from it.
update users set email = handle where email is null and handle like '%@%';

-- One account per email. Partial unique index tolerates legacy null emails.
create unique index if not exists users_email_key on users (lower(email)) where email is not null;
