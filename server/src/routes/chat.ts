import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { isMember } from '../services/chat.js';
import { ensureDirectConversation } from './social.js';

const r = Router();

// ── Conversation list with unread counts (drives the Chats tab) ──
r.get('/conversations', requireAuth, async (req, res) => {
  const rows = await db.any(
    `
    select c.id, c.is_group, c.group_id,
           g.name as group_name, g.icon_name as group_icon, g.icon_color as group_color,
           m.body as last_message, m.kind as last_kind, m.created_at as last_at,
           (select count(*) from messages x
            where x.conversation_id=c.id and x.created_at > cm.last_read_at
              and x.sender_id <> $1) as unread,
           -- the "other person" for 1:1 chats
           o.id as peer_id, o.display_name as peer_name, o.initial as peer_initial,
           o.avatar_color as peer_color, o.last_seen_at as peer_last_seen
    from conversation_members cm
    join conversations c on c.id = cm.conversation_id
    left join groups g on g.id = c.group_id
    left join lateral (
      select body, kind, created_at from messages
      where conversation_id=c.id order by created_at desc limit 1
    ) m on true
    left join lateral (
      select u.* from conversation_members cm2
      join users u on u.id = cm2.user_id
      where cm2.conversation_id=c.id and cm2.user_id <> $1 limit 1
    ) o on not c.is_group
    where cm.user_id=$1
    order by m.created_at desc nulls last`,
    [req.user.id],
  );
  res.json({ conversations: rows });
});

// ── Message history (keyset paginated, newest-last) ──
r.get('/conversations/:id/messages', requireAuth, async (req, res) => {
  if (!(await isMember(req.params.id, req.user.id))) {
    return res.status(403).json({ error: 'not a member' });
  }
  const { cursor } = req.query as { cursor?: string };
  const rows = await db.any(
    `select m.id, m.conversation_id, m.sender_id, m.body, m.kind, m.media_url,
            m.media_meta, m.created_at, m.client_temp_id, m.reply_to_id,
            u.display_name as sender_name, u.initial as sender_initial, u.avatar_color as sender_color,
            rm.body as reply_to_body, ru.display_name as reply_to_sender
     from messages m 
     join users u on u.id = m.sender_id
     left join messages rm on rm.id = m.reply_to_id
     left join users ru on ru.id = rm.sender_id
     where m.conversation_id=$1 ${cursor ? 'and m.created_at < $2' : ''}
     order by m.created_at desc limit 30`,
    cursor ? [req.params.id, cursor] : [req.params.id],
  );
  res.json({ messages: rows.reverse(), nextCursor: rows.at(0)?.created_at ?? null });
});

// ── Members of a conversation (drives the group "members" sheet) ──
// Returns only public identity (display name, initial, avatar colour) — never
// the email/handle. Member-gated so only people in the room can see the roster.
r.get('/conversations/:id/members', requireAuth, async (req, res) => {
  if (!(await isMember(req.params.id, req.user.id))) {
    return res.status(403).json({ error: 'not a member' });
  }
  const rows = await db.any(
    `select u.id, u.display_name, u.initial, u.avatar_color,
            (u.id = $2) as is_me
     from conversation_members cm
     join users u on u.id = cm.user_id
     where cm.conversation_id = $1
     order by is_me desc, u.display_name asc`,
    [req.params.id, req.user.id],
  );
  res.json({ members: rows });
});

// ── Open / create a 1:1 conversation (follow-gated) ──
r.post('/conversations/direct', requireAuth, async (req, res) => {
  const { userId } = req.body as { userId: string };
  if (!userId || userId === req.user.id) return res.status(400).json({ error: 'bad target' });

  // DMs are unlocked only between accepted friends (or an already-existing convo).
  const accepted = await db.oneOrNone(
    `select 1 from friendships
     where status='accepted'
       and ((requester_id=$1 and addressee_id=$2) or (requester_id=$2 and addressee_id=$1))`,
    [req.user.id, userId],
  );
  if (!accepted) {
    const existing = await db.oneOrNone(
      `select c.id from conversations c
       join conversation_members x on x.conversation_id=c.id and x.user_id=$1
       join conversation_members y on y.conversation_id=c.id and y.user_id=$2
       where c.is_group=false limit 1`,
      [req.user.id, userId],
    );
    if (!existing) return res.status(403).json({ error: 'follow request not accepted yet' });
    return res.json({ id: existing.id });
  }

  const id = await db.tx((t) => ensureDirectConversation(t, req.user.id, userId));
  res.json({ id });
});

// ── Mark read (clears the unread badge) ──
r.post('/conversations/:id/read', requireAuth, async (req, res) => {
  await db.none(
    `update conversation_members set last_read_at=now() where conversation_id=$1 and user_id=$2`,
    [req.params.id, req.user.id],
  );
  res.sendStatus(200);
});

export default r;
