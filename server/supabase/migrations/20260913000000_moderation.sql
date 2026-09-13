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

-- ============ ROW LEVEL SECURITY ============
--
-- Same shape as 20260826000000_security_hardening.sql, and for the same reason:
-- the API connects as the table owner and scopes every query in application
-- code, so this is defence in depth. It is the control that still holds if
-- anything else is ever pointed at this database - PostgREST with the anon key,
-- the Supabase client, a BI tool - and these two tables are the ones where that
-- matters most. user_blocks says who is avoiding whom; content_reports says who
-- reported whom and why. Neither should be readable by anything but the API.
--
-- `force` as well as `enable`, because `enable` alone exempts the table owner,
-- which is exactly the role the API connects as - the policies would otherwise
-- be decorative.
alter table user_blocks      enable row level security;
alter table user_blocks      force  row level security;
alter table content_reports  enable row level security;
alter table content_reports  force  row level security;

-- The API's role keeps full access, or every feed and chat request breaks the
-- moment RLS is forced above.
--
-- Derived from who owns an EXISTING table rather than from current_user, which
-- is what the earlier migration used. current_user is whoever happens to run
-- the file: run it from the Supabase SQL editor when the API connects as some
-- other role and the policy names the wrong one, locking the server out of the
-- tables it just created - with no error at migration time and a broken feed
-- afterwards. Whoever can already read `posts` is by definition the right role.
do $$
declare api_role text;
begin
  select pg_get_userbyid(relowner) into api_role
    from pg_class where oid = to_regclass('posts');
  if api_role is null then
    api_role := current_user;
  end if;

  execute format('drop policy if exists api_server_full_access on user_blocks');
  execute format(
    'create policy api_server_full_access on user_blocks to %I using (true) with check (true)',
    api_role);

  execute format('drop policy if exists api_server_full_access on content_reports');
  execute format(
    'create policy api_server_full_access on content_reports to %I using (true) with check (true)',
    api_role);
end $$;

-- Owner-only access for any other role, where Supabase provides auth.uid().
-- Deliberately absent for content_reports: a report is not the reporter's to
-- read back, and letting the reported party read it would identify whoever
-- reported them. Only the API sees that table.
do $$
begin
  if exists (select 1 from pg_proc where proname = 'uid'
               and pronamespace = (select oid from pg_namespace where nspname = 'auth')) then
    drop policy if exists own_rows on user_blocks;
    create policy own_rows on user_blocks
      using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());
  end if;
end $$;
