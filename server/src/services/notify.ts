import type { Server } from 'socket.io';
import { db } from '../db.js';
import { config } from '../config.js';
import type { AuthUser } from '../auth.js';

export type NotificationKind =
  | 'friend_request'
  | 'friend_accepted'
  | 'message'
  | 'friend_joined_room'
  | 'session_complete'
  | 'body_doubling_invite'
  | 'post_comment';

let io: Server;
export function initNotify(server: Server) {
  io = server;
}

/**
 * One entry point, dual delivery: socket if the user is online, FCM if not.
 * Every notification is also persisted so the bell/inbox can replay history.
 */
export async function pushNotification(
  userId: string,
  kind: NotificationKind,
  payload: Record<string, unknown>,
) {
  if (config.hasDb) {
    await db.none(`insert into notifications(user_id, kind, payload) values($1,$2,$3)`, [
      userId,
      kind,
      payload,
    ]);
  }

  const live = await io.in(`user:${userId}`).fetchSockets();
  if (live.length) {
    io.to(`user:${userId}`).emit('notification', { kind, payload });
  } else {
    await sendFcm(userId, kind, payload);
  }
}

/** "A friend joined a focus room" — fanned out to the joiner's accepted friends. */
export async function notifyFriendsJoinedRoom(user: AuthUser, roomId: string) {
  if (!config.hasDb) return; // no social graph without a DB (dev mode)
  const friends = await db.any<{ id: string }>(
    `select case when requester_id=$1 then addressee_id else requester_id end as id
     from friendships
     where status='accepted' and (requester_id=$1 or addressee_id=$1)`,
    [user.id],
  );
  const room = await db.oneOrNone<{ title: string }>(
    `select title from rooms where id=$1`,
    [roomId],
  );
  await Promise.all(
    friends.map((f) =>
      pushNotification(f.id, 'friend_joined_room', {
        userId: user.id,
        name: user.displayName,
        roomId,
        roomTitle: room?.title ?? 'a focus room',
      }),
    ),
  );
}

/** Push to every other member of a conversation who is currently offline. */
export async function fanoutChatPush(
  conversationId: string,
  senderId: string,
  preview: string,
) {
  if (!config.hasDb) return; // dev mode: live socket delivery only
  const members = await db.any<{ user_id: string }>(
    `select user_id from conversation_members where conversation_id=$1 and user_id<>$2`,
    [conversationId, senderId],
  );
  await Promise.all(
    members.map((m) =>
      pushNotification(m.user_id, 'message', { conversationId, senderId, preview }),
    ),
  );
}

// ── FCM (HTTP v1). Wire the firebase-admin SDK with FCM_SA_JSON in production. ──
async function sendFcm(userId: string, kind: NotificationKind, payload: Record<string, unknown>) {
  const row = await db.oneOrNone<{ fcm_token: string }>(
    `select fcm_token from users where id=$1`,
    [userId],
  );
  if (!row?.fcm_token) return;
  // TODO: getMessaging().send({ token: row.fcm_token, notification: titleFor(kind, payload), data })
  console.log(`[fcm] → ${userId} ${kind}`, payload);
}
