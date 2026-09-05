-- Motivation generation, metered apart from the coach.
--
-- The two were sharing coach_usage, which meant the day's motivation lines
-- spent the five daily messages the free tier promises for the conversation.
-- Two mood changes and the coach refused to talk, and because motivation fails
-- quietly into a written bank, the visible symptom was an app that seemed to
-- ignore the mood rather than one that was out of budget.
--
-- Same shape as coach_usage on purpose: keyed by the user's own local day, so
-- the allowance resets when their day does rather than at UTC midnight.
create table if not exists motivation_usage (
  user_id uuid not null references users(id) on delete cascade,
  day     date not null,
  count   integer not null default 0,
  primary key (user_id, day)
);

-- Only ever read for today, and only for one user.
create index if not exists motivation_usage_day_idx on motivation_usage (day);

-- Old buckets are of no interest once the day has passed.
delete from motivation_usage where day < current_date - 90;
