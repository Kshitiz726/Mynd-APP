-- Migration: 0004_comment_upvotes
-- Adds upvote functionality to comments

create table if not exists comment_upvotes (
  comment_id uuid not null references comments(id) on delete cascade,
  user_id    uuid not null references users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (comment_id, user_id)
);

create index if not exists comment_upvotes_comment_idx on comment_upvotes(comment_id);
