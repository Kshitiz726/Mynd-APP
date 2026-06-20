-- OurMynd 0002: media-in-chat, message idempotency, follow→DM provisioning.
-- Run: psql "$DATABASE_URL" -f supabase/migrations/0002_chat_media_social.sql
--   or: npm run migrate  (applies every file in migrations/ in order)

-- ============ MESSAGE KINDS + MEDIA ============
do $$ begin
  create type message_kind as enum ('text','image','file');
exception when duplicate_object then null; end $$;

alter table messages add column if not exists kind        message_kind not null default 'text';
alter table messages add column if not exists media_url    text;
alter table messages add column if not exists media_meta   jsonb;          -- { name, mime, size, width, height }
-- The client's optimistic temp id. Lets the persist step be idempotent so a
-- socket retry / double-send can never create a duplicate row, and lets clients
-- reconcile the optimistic bubble even if they reconnect mid-flight.
alter table messages add column if not exists client_temp_id text;

-- A non-empty body OR a media payload — never a blank message row.
alter table messages drop constraint if exists messages_has_content;
alter table messages add  constraint messages_has_content
  check (kind <> 'text' or char_length(btrim(body)) > 0);

-- One row per (sender, client_temp_id): the idempotency key for optimistic sends.
create unique index if not exists messages_idem_idx
  on messages (sender_id, client_temp_id) where client_temp_id is not null;

-- ============ SOCIAL GRAPH HELPERS ============
-- Fast "who follows me / pending requests for me" lookups already exist via
-- friendships_addressee_idx. Add the reverse for "my outgoing requests".
create index if not exists friendships_requester_idx on friendships (requester_id, status);

-- ============ NOTIFICATION READ-CURSOR ============
-- (notifications table + unread index already created in 0001.) Nothing to add;
-- the alerts inbox reads notifications directly and the friend_request /
-- friend_accepted kinds are written by the social route.
