import { Router } from 'express';
import type { ITask } from 'pg-promise';
import { db } from '../db.js';
import { isBlockedBetween } from '../services/moderation.js';
import { requireAuth } from '../auth.js';
import { pushNotification } from '../services/notify.js';

const r = Router();

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers (also reused by the chat route).
// ─────────────────────────────────────────────────────────────────────────────

/** Idempotently resolve the one conversation backing a group, joining the user. */
export async function ensureGroupConversation(
  t: ITask<unknown>,
  groupId: string,
  userId: string,
): Promise<string> {
  // 404-able existence check first → a bad/stale group id returns a clean error
  // instead of a 500 from a FK violation (a source of "couldn't open chat").
  const group = await t.oneOrNone(`select id from groups where id=$1`, [groupId]);
  if (!group) throw Object.assign(new Error('group not found'), { status: 404 });

  const ins = await t.result(
    `insert into group_members(group_id, user_id) values($1,$2) on conflict do nothing`,
    [groupId, userId],
  );
  if (ins.rowCount > 0) {
    await t.none(`update groups set member_count = member_count + 1 where id=$1`, [groupId]);
  }

  let convo = await t.oneOrNone(
    `select id from conversations where group_id=$1 and is_group=true limit 1`,
    [groupId],
  );
  convo ??= await t.one(
    `insert into conversations(is_group, group_id) values(true,$1) returning id`,
    [groupId],
  );
  await t.none(
    `insert into conversation_members(conversation_id, user_id) values($1,$2) on conflict do nothing`,
    [convo.id, userId],
  );
  return convo.id as string;
}

/** Idempotently resolve the 1:1 DM conversation between two users. */
export async function ensureDirectConversation(
  t: ITask<unknown>,
  a: string,
  b: string,
): Promise<string> {
  const existing = await t.oneOrNone(
    `select c.id from conversations c
     join conversation_members x on x.conversation_id=c.id and x.user_id=$1
     join conversation_members y on y.conversation_id=c.id and y.user_id=$2
     where c.is_group=false limit 1`,
    [a, b],
  );
  if (existing) return existing.id as string;
  const c = await t.one(`insert into conversations(is_group) values(false) returning id`);
  await t.none(
    `insert into conversation_members(conversation_id, user_id) values($1,$2),($1,$3)`,
    [c.id, a, b],
  );
  return c.id as string;
}

/** Friendship status between me and another user, normalised to my POV. */
async function friendshipState(me: string, other: string) {
  const row = await db.oneOrNone<{ status: string; outgoing: boolean }>(
    `select status, (requester_id=$1) as outgoing from friendships
     where (requester_id=$1 and addressee_id=$2) or (requester_id=$2 and addressee_id=$1)
     limit 1`,
    [me, other],
  );
  return row; // null = no relationship
}

// ─────────────────────────────────────────────────────────────────────────────
// Friend / follow requests
// ─────────────────────────────────────────────────────────────────────────────

r.post('/friends/request', requireAuth, async (req, res) => {
  // A block is not a mute: somebody you blocked must not be able to put a
  // friend request in front of you. Same 400 in both directions, so the
  // endpoint does not become a way to discover that you were blocked.
  if (await isBlockedBetween(db, req.user.id, (req.body as { userId?: string }).userId ?? '')) {
    return res.status(400).json({ error: 'cannot send that request' });
  }
  const { userId } = req.body as { userId: string };
  if (!userId || userId === req.user.id) return res.status(400).json({ error: 'bad target' });
  await db.none(
    `insert into friendships(requester_id, addressee_id) values($1,$2)
     on conflict (requester_id, addressee_id) do nothing`,
    [req.user.id, userId],
  );
  await pushNotification(userId, 'friend_request', {
    from: req.user.id,
    name: req.user.displayName,
  });
  res.status(201).json({ ok: true });
});

// Accept → provision the DM immediately and hand both sides its conversation id.
r.post('/friends/respond', requireAuth, async (req, res) => {
  const { requesterId, accept } = req.body as { requesterId: string; accept: boolean };
  const result = await db.tx(async (t) => {
    const upd = await t.result(
      `update friendships set status=$3, responded_at=now()
       where requester_id=$1 and addressee_id=$2 and status='pending'`,
      [requesterId, req.user.id, accept ? 'accepted' : 'rejected'],
    );
    if (upd.rowCount === 0) return { conversationId: null as string | null };
    if (!accept) return { conversationId: null as string | null };
    const conversationId = await ensureDirectConversation(t, req.user.id, requesterId);
    return { conversationId };
  });

  if (accept && result.conversationId) {
    // Tell the original requester their request was accepted + unlock their DM.
    await pushNotification(requesterId, 'friend_accepted', {
      userId: req.user.id,
      name: req.user.displayName,
      conversationId: result.conversationId,
    });
  }
  res.json(result);
});

// Full friends list (accepted both ways + pending), my POV.
r.get('/friends', requireAuth, async (req, res) => {
  const rows = await db.any(
    `select u.id, u.display_name, u.initial, u.avatar_color, f.status,
            (f.requester_id = $1) as outgoing
     from friendships f
     join users u on u.id = case when f.requester_id=$1 then f.addressee_id else f.requester_id end
     where f.requester_id=$1 or f.addressee_id=$1
     order by f.created_at desc`,
    [req.user.id],
  );
  res.json({ friends: rows });
});

// Incoming pending requests only - drives the Alerts "follow requests" section.
r.get('/friends/requests', requireAuth, async (req, res) => {
  const rows = await db.any(
    `select u.id, u.display_name, u.initial, u.avatar_color, f.created_at
     from friendships f join users u on u.id = f.requester_id
     where f.addressee_id=$1 and f.status='pending'
     order by f.created_at desc`,
    [req.user.id],
  );
  res.json({ requests: rows });
});

// ─────────────────────────────────────────────────────────────────────────────
// User profile (drives the in-chat profile sheet)
// ─────────────────────────────────────────────────────────────────────────────

r.get('/users/:id', requireAuth, async (req, res) => {
  const u = await db.oneOrNone(
    `select id, display_name, initial, avatar_color, current_energy, last_seen_at,
            avatar_updated_at, (avatar_image is not null) as has_avatar
     from users where id=$1`,
    [req.params.id],
  );
  if (!u) return res.status(404).json({ error: 'not found' });
  u.avatar_url = u.has_avatar
    ? `/api/users/${u.id}/avatar?v=${new Date(u.avatar_updated_at ?? 0).getTime()}`
    : null;
  const isMe = u.id === req.user.id;
  const fs = isMe ? null : await friendshipState(req.user.id, u.id);
  // NOTE: `handle` is the user's Google email - it is deliberately NOT selected
  // or returned here so it never surfaces in the in-chat profile sheet. The
  // anonymous display_name is the only public identity.
  res.json({
    user: u,
    isMe,
    friendship: fs, // { status, outgoing } | null
    canDm: isMe || fs?.status === 'accepted',
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Groups
// ─────────────────────────────────────────────────────────────────────────────

// Suggested groups: exactly N (default 5) the user has NOT joined, most popular
// first - the "Groups for you" rail.
r.get('/groups/suggested', requireAuth, async (req, res) => {
  const limit = Math.min(Number(req.query.limit ?? 5) || 5, 20);
  const rows = await db.any(
    `select g.* from groups g
     where not exists (select 1 from group_members m where m.group_id=g.id and m.user_id=$1)
     order by g.member_count desc, g.name asc
     limit $2`,
    [req.user.id, limit],
  );
  res.json({ groups: rows.map((g) => ({ ...g, joined: false })) });
});

// Joined groups - "Your groups". Includes the conversation id so tapping opens
// the chat directly with no extra round-trip.
r.get('/groups/mine', requireAuth, async (req, res) => {
  const rows = await db.any(
    `select g.*, c.id as conversation_id
     from group_members gm
     join groups g on g.id = gm.group_id
     left join conversations c on c.group_id = g.id and c.is_group = true
     where gm.user_id=$1
     order by gm.joined_at desc`,
    [req.user.id],
  );
  res.json({ groups: rows.map((g) => ({ ...g, joined: true })) });
});

// Back-compat: all groups with a joined flag.
r.get('/groups', requireAuth, async (req, res) => {
  const rows = await db.any(
    `select g.*, exists(select 1 from group_members m
                        where m.group_id=g.id and m.user_id=$1) as joined
     from groups g order by g.member_count desc`,
    [req.user.id],
  );
  res.json({ groups: rows });
});

// Join a group AND open its chat (idempotent). Returns the conversation id.
r.post('/groups/:id/join', requireAuth, async (req, res, next) => {
  try {
    const conversationId = await db.tx((t) => ensureGroupConversation(t, req.params.id, req.user.id));
    res.json({ conversationId });
  } catch (e) {
    next(e);
  }
});

// Resolve the chat for a group WITHOUT changing membership counts beyond
// ensuring the row exists. Used by "Your groups" → Open and as the bug-proof
// path that always yields a valid, member-scoped conversation id.
r.get('/groups/:id/conversation', requireAuth, async (req, res, next) => {
  try {
    const conversationId = await db.tx((t) => ensureGroupConversation(t, req.params.id, req.user.id));
    res.json({ conversationId });
  } catch (e) {
    next(e);
  }
});

export default r;
