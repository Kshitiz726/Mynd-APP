import { Router } from 'express';
import type { Server } from 'socket.io';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { pushNotification } from '../services/notify.js';

/**
 * Body doubling: pair two people into a private focus room so they can work
 * "alongside" each other. Two ways in:
 *   1. Auto-match - join a queue; the moment another solo user is waiting, we
 *      pair you both into a fresh private room and push `bd_matched` to each.
 *   2. Invite a friend - create the room now and notify a specific friend.
 *
 * The queue is in-process (single Node instance, fine for early rollout). Each
 * waiting entry remembers the user's profile so the partner card can render
 * immediately without an extra fetch.
 */

interface PublicProfile {
  id: string;
  displayName: string;
  initial: string;
  avatarColor: string | null;
  /** Their picture, if they have set one. Null falls back to the initial. */
  avatarUrl: string | null;
}

interface WaitingEntry {
  profile: PublicProfile;
  since: number;
}

export function bodyDoublingRouter(io: Server) {
  const r = Router();

  // userId → waiting entry. A user can only sit in the queue once.
  const queue = new Map<string, WaitingEntry>();

  async function profileOf(userId: string): Promise<PublicProfile> {
    const u = await db.one(
      `select id, display_name, initial, avatar_color, avatar_updated_at,
              (avatar_image is not null) as has_avatar
       from users where id=$1`,
      [userId],
    );
    return {
      id: u.id,
      displayName: u.display_name,
      initial: u.initial,
      avatarColor: u.avatar_color,
      // Stamped so a partner who changed their picture mid-session is not
      // shown behind yesterday's cached one.
      avatarUrl: u.has_avatar
        ? `/api/users/${u.id}/avatar?v=${new Date(u.avatar_updated_at ?? 0).getTime()}`
        : null,
    };
  }

  // Spin up a private, ad-hoc body-doubling room owned by `hostId`.
  async function createRoom(hostId: string, title = 'Body Doubling'): Promise<{ id: string; title: string }> {
    const slug = `bd-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
    const room = await db.one(
      `insert into rooms(title, icon_name, icon_color, default_ambience, visibility, livekit_room, host_id)
       values($1,'users','#6B70C9','cafe','private',$2,$3) returning id, title`,
      [title, slug, hostId],
    );
    return { id: room.id, title: room.title };
  }

  // ── Auto-match: pair with a waiting user, else queue up. ──
  r.post('/body-doubling/match', requireAuth, async (req, res, next) => {
    try {
      const me = req.user.id;
      queue.delete(me); // never match with myself / stale self entry

      // Find the longest-waiting partner.
      const partnerEntry = [...queue.values()].sort((a, b) => a.since - b.since)[0];
      if (partnerEntry) {
        const partnerId = partnerEntry.profile.id;
        queue.delete(partnerId);

        const room = await createRoom(me);
        const myProfile = await profileOf(me);

        // Push each side the OTHER person's card + the shared room.
        io.to(`user:${partnerId}`).emit('bd_matched', {
          roomId: room.id,
          roomTitle: room.title,
          partner: myProfile,
        });
        return res.json({ matched: true, roomId: room.id, roomTitle: room.title, partner: partnerEntry.profile });
      }

      // Nobody waiting → join the queue.
      queue.set(me, { profile: await profileOf(me), since: Date.now() });
      res.json({ matched: false, waiting: true });
    } catch (e) {
      next(e);
    }
  });

  // ── Stop waiting (user left the matchmaking screen). ──
  r.post('/body-doubling/cancel', requireAuth, async (req, res) => {
    queue.delete(req.user.id);
    res.json({ ok: true });
  });

  // ── Invite a specific friend into a new body-doubling room. ──
  r.post('/body-doubling/invite', requireAuth, async (req, res, next) => {
    try {
      const { userId } = req.body as { userId: string };
      if (!userId || userId === req.user.id) return res.status(400).json({ error: 'bad target' });

      // Only invite accepted friends.
      const friend = await db.oneOrNone(
        `select 1 from friendships
         where status='accepted'
           and ((requester_id=$1 and addressee_id=$2) or (requester_id=$2 and addressee_id=$1))
         limit 1`,
        [req.user.id, userId],
      );
      if (!friend) return res.status(403).json({ error: 'not friends' });

      const room = await createRoom(req.user.id);
      await pushNotification(userId, 'body_doubling_invite', {
        roomId: room.id,
        roomTitle: room.title,
        fromId: req.user.id,
        fromName: req.user.displayName,
      });
      res.json({ roomId: room.id, roomTitle: room.title });
    } catch (e) {
      next(e);
    }
  });

  return r;
}
