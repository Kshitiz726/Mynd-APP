-- Dev-only seed: a current user (Sam) + Maya/Leo and the two posts shown in the
-- Community UI, so the feed renders real data. Applied by `npm run dev:full`.
-- Stable UUIDs so the dev-token endpoint can mint a token for a known user.

insert into users (id, handle, display_name, avatar_color, avatar_text_color, current_energy)
values
  ('11111111-1111-1111-1111-111111111111', 'sam',  'Sam',  '#E0E7FF', '#4F46E5', 'low'),
  ('22222222-2222-2222-2222-222222222222', 'maya', 'Maya', '#E0E7FF', '#4F46E5', 'low'),
  ('33333333-3333-3333-3333-333333333333', 'leo',  'Leo',  '#FCE7F3', '#DB2777', 'high')
on conflict (id) do nothing;

-- Maya's post (#Study #Struggles, Low Energy)
insert into posts (id, author_id, body, mood, relate_count, support_count, comment_count)
values (
  'aaaaaaaa-0000-0000-0000-000000000001',
  '22222222-2222-2222-2222-222222222222',
  'Been struggling to start my essay for 3 days. My brain just won''t engage.',
  'low', 12, 3, 4
) on conflict (id) do nothing;
insert into post_tags (post_id, tag) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'study'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 'struggles')
on conflict do nothing;

-- Leo's post (#Medication #Wins, Energized)
insert into posts (id, author_id, body, mood, proud_count, comment_count)
values (
  'aaaaaaaa-0000-0000-0000-000000000002',
  '33333333-3333-3333-3333-333333333333',
  'Started a new medication today and I finally feel clear. Just wanted to share the win!',
  'high', 8, 1
) on conflict (id) do nothing;
insert into post_tags (post_id, tag) values
  ('aaaaaaaa-0000-0000-0000-000000000002', 'medication'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 'wins')
on conflict do nothing;

-- A DM thread so the Chats tab has content.
insert into conversations (id, is_group) values
  ('cccccccc-0000-0000-0000-000000000001', false)
on conflict (id) do nothing;
insert into conversation_members (conversation_id, user_id) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111'),
  ('cccccccc-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222')
on conflict do nothing;
insert into messages (conversation_id, sender_id, body) values
  ('cccccccc-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222',
   'Maya invited you to a Cafe Study Session.')
on conflict do nothing;

-- ── 5 ADHD-themed groups + their (one-per-group) chat conversations ──
insert into groups (id, name, icon_name, icon_color, member_count) values
  ('99990000-0000-0000-0000-000000000001', 'ADHD Students',  'brain',    '#6B70C9', 4200),
  ('99990000-0000-0000-0000-000000000002', 'Night Owls',     'moon',     '#8A86A6', 1800),
  ('99990000-0000-0000-0000-000000000003', 'Creative Minds', 'sparkles', '#EC4899', 3500),
  ('99990000-0000-0000-0000-000000000004', 'Focus & Flow',   'target',   '#6FB28C', 2600),
  ('99990000-0000-0000-0000-000000000005', 'Body Doubling',  'users',    '#F0A479', 3100)
on conflict (id) do nothing;

insert into conversations (id, is_group, group_id) values
  ('99991111-0000-0000-0000-000000000001', true, '99990000-0000-0000-0000-000000000001'),
  ('99991111-0000-0000-0000-000000000002', true, '99990000-0000-0000-0000-000000000002'),
  ('99991111-0000-0000-0000-000000000003', true, '99990000-0000-0000-0000-000000000003'),
  ('99991111-0000-0000-0000-000000000004', true, '99990000-0000-0000-0000-000000000004'),
  ('99991111-0000-0000-0000-000000000005', true, '99990000-0000-0000-0000-000000000005')
on conflict (id) do nothing;

-- Seed messages so the group chats aren't empty (fixed ids → idempotent).
insert into messages (id, conversation_id, sender_id, body) values
  ('99992222-0000-0000-0000-000000000001', '99991111-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Welcome to ADHD Students! What are you working on today?'),
  ('99992222-0000-0000-0000-000000000002', '99991111-0000-0000-0000-000000000003', '33333333-3333-3333-3333-333333333333', 'Drop your current creative project below 👇'),
  ('99992222-0000-0000-0000-000000000003', '99991111-0000-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'Anyone want to body-double for the next 25 min?')
on conflict (id) do nothing;
