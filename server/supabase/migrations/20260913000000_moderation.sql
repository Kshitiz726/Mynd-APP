-- Blocking and reporting.
--
-- App Store Review Guideline 1.2 requires four things of any app carrying
-- user-generated content: a way to filter objectionable content, a way to
-- report it, a way to block abusive users, and published contact details. This
-- app has a public feed, comments, direct messages, focus rooms and live voice,
-- and had none of the four. Live voice raises the bar rather than lowering it -
-- a stranger can speak into your ear.
--
-- Blocking is stored one-directional and enforced symmetrically. Storing it
-- both ways would double the rows and make unblocking ambiguous; reading it
-- both ways is what people actually expect, and it closes the hole where
-- someone you blocked can still watch you.

create table if not exists user_blocks (
  blocker_id uuid not null references users(id) on delete cascade,
  blocked_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  -- Blocking yourself is always a bug, never an intent.
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

-- The reverse direction is read on every feed query ("did they block me?"), so
-- it needs its own index; the primary key only serves the forward one.
create index if not exists user_blocks_blocked_idx on user_blocks (blocked_id);

create table if not exists content_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references users(id) on delete cascade,
  -- Not a foreign key: one column points at five different tables, and the
  -- report must outlive the thing it is about. A report whose evidence is
  -- deleted the moment the author tidies up is worthless.
  target_type text not null check (target_type in ('post','comment','message','user','room')),
  target_id   uuid not null,
  reason      text not null check (reason in
                ('spam','harassment','hate','sexual','violence','self_harm','other')),
  -- What the reporter typed, and a copy of what they were looking at. Kept
  -- because the content can be edited or deleted before anyone reads this.
  note        text,
  snapshot    text,
  status      text not null default 'open'
                check (status in ('open','reviewed','actioned','dismissed')),
  created_at  timestamptz not null default now()
);

-- The triage order: oldest open report first.
create index if not exists content_reports_open_idx
  on content_reports (status, created_at);

-- One report per person per thing. Without this, "report" becomes a button
-- somebody taps forty times, and the queue becomes unreadable exactly when it
-- matters. Changing your mind about the reason is an update, not a new row.
create unique index if not exists content_reports_one_per_reporter
  on content_reports (reporter_id, target_type, target_id);
