-- OurMynd: user-chosen identity, and per-account state that follows the person
-- rather than the phone.
--
-- Run: psql "$DATABASE_URL" -f supabase/migrations/20260815000000_profile_and_state.sql
--   or: npm run migrate

-- ============ PROFILE PICTURE + CHOSEN NAME ============
-- 0003 deliberately kept everyone anonymous behind a generated handle. That has
-- been reversed by product decision: people set their own name and picture, and
-- body doubling shows you who you are actually sitting with.
--
-- The image is stored inline rather than in object storage. At the size we
-- accept (a square thumbnail, capped below) a row is a few tens of KB, which
-- Postgres stores out-of-line in TOAST and never reads unless asked for. It is
-- served by its own endpoint, so listing a hundred users never carries a
-- hundred images. If avatars ever grow, this becomes a bucket URL and the
-- endpoint stays the same shape.
alter table users add column if not exists avatar_image      text;
alter table users add column if not exists avatar_mime       text;
alter table users add column if not exists avatar_updated_at timestamptz;

-- Whether display_name is theirs or still the generated one. Lets the app
-- prompt once for a real name without nagging someone who likes the handle.
alter table users add column if not exists name_chosen boolean not null default false;

-- Everyone created before this point has a generated name by definition.
update users set name_chosen = false where name_chosen is null;

-- ============ PER-ACCOUNT STATE ============
-- The backlog, the day's schedule, goals and habits all lived only in the
-- phone's SharedPreferences, which made them device data wearing an account's
-- clothes: sign in on a second device and your backlog was not there.
--
-- One generic key/value table rather than a table per feature. These are opaque
-- JSON documents owned entirely by the client, and the server's job is to hold
-- the newest one, not to understand it. A schema per feature would have to be
-- migrated in lockstep with the app for no benefit.
--
-- Conflict resolution is last-write-wins on updated_at, which is honest for a
-- single-user-at-a-time document and avoids inventing a merge nobody asked for.
create table if not exists user_state (
  user_id    uuid not null references users(id) on delete cascade,
  key        text not null,
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);
