-- OurMynd initial schema. Target: Supabase / managed Postgres (NOT sqlite).
-- Run: psql "$DATABASE_URL" -f supabase/migrations/0001_init.sql
--   or: supabase db push

create extension if not exists ltree;
create extension if not exists pgcrypto;     -- gen_random_uuid()
create extension if not exists btree_gist;   -- gist index over (uuid, ltree)

-- ============ ENUMS (mirror the Flutter enums exactly) ============
do $$ begin
  create type energy_level      as enum ('high','low','dead');
  create type reaction_kind     as enum ('relate','support','proud');
  create type room_status       as enum ('live','scheduled','ended');
  create type session_status    as enum ('running','paused','completed','abandoned');
  create type participant_state as enum ('active','inactive','muted','need_help');
  create type friendship_status as enum ('pending','accepted','rejected','blocked');
  create type ambience_kind     as enum ('silent','rain','cafe','library','typing');
  create type focus_mode_kind   as enum ('sprint','pomodoro','deep_work','flow','custom');
exception when duplicate_object then null; end $$;

-- Added after initial release → separate block so it still creates on an
-- already-migrated DB (the block above aborts on the first duplicate type).
do $$ begin
  create type room_visibility as enum ('public','private');
exception when duplicate_object then null; end $$;

-- ============ USERS ============
create table if not exists users (
  id                uuid primary key default gen_random_uuid(),
  handle            text unique not null,
  display_name      text not null,
  avatar_color      text,
  avatar_text_color text,
  initial           char(1) generated always as (upper(left(display_name,1))) stored,
  current_energy    energy_level,
  fcm_token         text,
  last_seen_at      timestamptz default now(),
  created_at        timestamptz default now()
);
create index if not exists users_last_seen_idx on users (last_seen_at desc);

-- ============ POSTS / FEED ============
create table if not exists posts (
  id            uuid primary key default gen_random_uuid(),
  author_id     uuid not null references users(id) on delete cascade,
  body          text not null check (char_length(body) <= 1000),
  mood          energy_level,
  created_at    timestamptz default now(),
  comment_count int default 0,
  relate_count  int default 0,
  support_count int default 0,
  proud_count   int default 0
);
create index if not exists posts_feed_idx on posts (created_at desc);

create table if not exists post_tags (
  post_id uuid references posts(id) on delete cascade,
  tag     text not null,
  primary key (post_id, tag)
);
create index if not exists post_tags_tag_idx on post_tags (tag, post_id);

-- ============ REACTIONS ENGINE (stateful, one row per user per kind) ============
create table if not exists reactions (
  post_id    uuid references posts(id) on delete cascade,
  user_id    uuid references users(id)  on delete cascade,
  kind       reaction_kind not null,
  created_at timestamptz default now(),
  primary key (post_id, user_id, kind)
);

create or replace function bump_reaction_count() returns trigger as $$
declare delta int; col text;
begin
  delta := case when tg_op='INSERT' then 1 else -1 end;
  col   := case coalesce(new.kind, old.kind)
             when 'relate'  then 'relate_count'
             when 'support' then 'support_count'
             when 'proud'   then 'proud_count' end;
  execute format('update posts set %I = %I + $1 where id = $2', col, col)
    using delta, coalesce(new.post_id, old.post_id);
  return null;
end $$ language plpgsql;

drop trigger if exists trg_reaction_count on reactions;
create trigger trg_reaction_count
  after insert or delete on reactions
  for each row execute function bump_reaction_count();

-- ============ NESTED COMMENTS (adjacency list + ltree path) ============
create table if not exists comments (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references posts(id) on delete cascade,
  author_id  uuid not null references users(id) on delete cascade,
  parent_id  uuid references comments(id) on delete cascade,
  body       text not null,
  path       ltree not null,
  created_at timestamptz default now()
);
create index if not exists comments_post_path_idx on comments using gist (post_id, path);

create or replace function bump_comment_count() returns trigger as $$
begin
  if tg_op='INSERT' then update posts set comment_count = comment_count + 1 where id = new.post_id;
  else                    update posts set comment_count = comment_count - 1 where id = old.post_id;
  end if;
  return null;
end $$ language plpgsql;
drop trigger if exists trg_comment_count on comments;
create trigger trg_comment_count after insert or delete on comments
  for each row execute function bump_comment_count();

-- ============ SOCIAL GRAPH ============
create table if not exists friendships (
  requester_id uuid references users(id) on delete cascade,
  addressee_id uuid references users(id) on delete cascade,
  status       friendship_status not null default 'pending',
  created_at   timestamptz default now(),
  responded_at timestamptz,
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create index if not exists friendships_addressee_idx on friendships (addressee_id, status);

create table if not exists groups (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  icon_name    text,
  icon_color   text,
  member_count int default 0
);
create table if not exists group_members (
  group_id  uuid references groups(id) on delete cascade,
  user_id   uuid references users(id)  on delete cascade,
  joined_at timestamptz default now(),
  primary key (group_id, user_id)
);

-- ============ FOCUS ROOMS ============
create table if not exists rooms (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  icon_name        text,
  icon_color       text,
  status           room_status default 'live',
  default_ambience ambience_kind default 'cafe',
  livekit_room     text unique not null,
  host_id          uuid references users(id),
  max_participants int default 100,
  created_at       timestamptz default now()
  -- live participant count is NOT stored here; it lives in Redis.
);
-- Visibility: public rooms appear in everyone's list; private rooms are
-- join-by-link only. Added via alter so existing clusters pick it up too.
alter table rooms add column if not exists visibility room_visibility default 'public';
create index if not exists rooms_public_idx on rooms (visibility, status, created_at desc);

-- ============ FOCUS SESSIONS ============
create table if not exists sessions (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  room_id        uuid references rooms(id) on delete set null,
  task           text,
  mode           focus_mode_kind not null,
  duration_secs  int not null,
  status         session_status default 'running',
  body_doubling  bool default false,
  ambience       ambience_kind default 'silent',
  started_at     timestamptz default now(),
  ended_at       timestamptz,
  completed_secs int
);
create index if not exists sessions_user_idx on sessions (user_id, started_at desc);

-- ============ CHAT ============
create table if not exists conversations (
  id         uuid primary key default gen_random_uuid(),
  is_group   bool default false,
  group_id   uuid references groups(id),
  created_at timestamptz default now()
);
create table if not exists conversation_members (
  conversation_id uuid references conversations(id) on delete cascade,
  user_id         uuid references users(id) on delete cascade,
  last_read_at    timestamptz default now(),
  primary key (conversation_id, user_id)
);
create table if not exists messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id       uuid not null references users(id),
  body            text not null,
  created_at      timestamptz default now()
);
create index if not exists messages_convo_idx on messages (conversation_id, created_at desc);

-- ============ NOTIFICATIONS ============
create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id) on delete cascade,
  kind       text not null,
  payload    jsonb not null,
  read_at    timestamptz,
  created_at timestamptz default now()
);
create index if not exists notifications_unread_idx
  on notifications (user_id, created_at desc) where read_at is null;

-- ============ ROW-LEVEL SECURITY (Supabase) ============
-- A user can only read DMs in conversations they belong to. Guarded so the
-- same migration also runs on plain Postgres (local/embedded dev), where
-- Supabase's auth.uid() doesn't exist — there the Node server connects as
-- owner and enforces access in the query layer instead.
do $$ begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'auth' and p.proname = 'uid'
  ) then
    execute 'alter table messages enable row level security';
    execute 'drop policy if exists "read own convos" on messages';
    execute $p$create policy "read own convos" on messages for select
      using (exists (select 1 from conversation_members m
                     where m.conversation_id = messages.conversation_id
                       and m.user_id = auth.uid()))$p$;
  end if;
end $$;

-- ============ SEED: the rooms + groups shown in the UI ============
insert into rooms (title, icon_name, icon_color, default_ambience, livekit_room)
values
  ('Café Study Room', 'coffee',   '#9A7B4F', 'cafe',    'cafe-study'),
  ('Deep Work Room',  'brain',    '#2F6E8F', 'silent',  'deep-work'),
  ('Deep Work Studio','keyboard', '#5C9E72', 'typing',  'deep-work-studio')
on conflict (livekit_room) do nothing;

-- (Groups are seeded idempotently in supabase/seed_dev.sql, not here — a
-- migration must not insert duplicate rows on every boot.)
