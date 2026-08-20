import type { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { pubClient, subClient } from '../redis.js';
import { verifyJwt, type AuthUser } from '../auth.js';
import { AccessToken } from 'livekit-server-sdk';
import { config } from '../config.js';
import { makePresence } from './presence.js';
import { toggleReaction, type ReactionKind } from '../services/reactions.js';
import { persistMessage, isMember, otherMemberIds, type MessageKind, type MediaMeta } from '../services/chat.js';
import { notifyFriendsJoinedRoom, fanoutChatPush, pushNotification } from '../services/notify.js';

export function attachRealtime(io: Server) {
  // Multi-node fanout only when real Redis is configured; dev mode runs the
  // default single-node in-memory adapter.
  if (config.hasRedis) {
    io.adapter(createAdapter(pubClient, subClient));
  }
  const presence = makePresence(io);

  // ── Auth handshake: no valid token, no socket ──
  io.use(async (socket, next) => {
    try {
      socket.data.user = await verifyJwt(socket.handshake.auth?.token);
      next();
    } catch {
      next(new Error('unauthorized'));
    }
  });

  io.on('connection', (socket) => {
    const user: AuthUser = socket.data.user;
    socket.data.rooms = new Set<string>();
    socket.join(`user:${user.id}`); // personal room for DMs + notifications
    socket.join('lobby'); // receives room-list updates (new public rooms, counts)

    // ════════════ FOCUS ROOM ════════════
    socket.on('join_room', async ({ roomId }: { roomId: string }) => {
      const view = await presence.join(roomId, user, socket.id);
      socket.join(`room:${roomId}`);
      socket.data.rooms.add(roomId);

      const snapshot = await presence.snapshot(roomId);
      socket.emit('room_state', snapshot); // full snapshot to joiner
      socket.to(`room:${roomId}`).emit('participant_joined', {
        roomId,
        participant: view,
        count: snapshot.participantCount,
      });
      io.to(`room:${roomId}`).emit('room_count_update', {
        roomId,
        count: snapshot.participantCount,
      });
      // Update everyone's room list + global "minds focusing" counter.
      io.to('lobby').emit('room_live_update', { roomId, count: snapshot.participantCount });
      io.to('lobby').emit('global_focus_update', { count: await presence.globalFocusingCount() });
      await notifyFriendsJoinedRoom(user, roomId);
    });

    socket.on('leave_room', async ({ roomId }: { roomId: string }) => {
      socket.leave(`room:${roomId}`);
      socket.data.rooms.delete(roomId);
      await presence.leave(roomId, user.id, socket.id);
    });

    socket.on('heartbeat', async ({ roomId }: { roomId: string }) => {
      await presence.heartbeat(roomId, user.id);
    });

    // ── Voice: mint a LiveKit token (authorization, not SDP relay) ──
    socket.on('voice_join', async ({ roomId }: { roomId: string }) => {
      if (!(await presence.isInRoom(roomId, user.id))) return;
      if (!config.hasLivekit) {
        socket.emit('voice_unavailable', { roomId, reason: 'LiveKit not configured' });
        return;
      }
      const at = new AccessToken(config.livekit.apiKey, config.livekit.apiSecret, {
        identity: user.id,
        name: user.displayName,
        ttl: '4h',
      });
      at.addGrant({
        roomJoin: true,
        room: `room:${roomId}`,
        canPublish: true, // audio only
        canSubscribe: true,
        canPublishData: false,
      });
      socket.emit('voice_token', {
        roomId,
        livekitUrl: config.livekit.url,
        token: await at.toJwt(),
      });
    });

    // ── Mic state (visual grid only - the real track lives in LiveKit) ──
    socket.on('toggle_mute', async ({ roomId, muted }: { roomId: string; muted: boolean }) => {
      await presence.patch(roomId, user.id, {
        micState: muted ? 'muted' : 'speaking',
        state: muted ? 'muted' : 'active',
      });
      io.to(`room:${roomId}`).emit('participant_update', {
        roomId,
        userId: user.id,
        patch: { micState: muted ? 'muted' : 'speaking', state: muted ? 'muted' : 'active' },
      });
    });

    socket.on('ptt_state', async ({ roomId, talking }: { roomId: string; talking: boolean }) => {
      io.to(`room:${roomId}`).emit('participant_update', {
        roomId,
        userId: user.id,
        patch: { micState: talking ? 'ptt' : 'muted' },
      });
    });

    // ── "Need help" / presence state ──
    socket.on('set_state', async ({ roomId, state }: { roomId: string; state: 'active' | 'inactive' | 'need_help' }) => {
      await presence.patch(roomId, user.id, { state });
      io.to(`room:${roomId}`).emit('participant_update', { roomId, userId: user.id, patch: { state } });
    });

    // ── Session / timer (server is the clock authority) ──
    // `mode` must be a `focus_mode_kind`; anything else (a task title from an
    // older/looser client) is coerced to 'custom' so a bad value can never
    // reach the enum column - and the whole handler is guarded so even an
    // unexpected DB error only drops this one event instead of crashing the
    // process for every connected user.
    socket.on('set_session', async ({ roomId, task, mode, durationSecs }: { roomId: string; task: string; mode: string; durationSecs: number }) => {
      const VALID_MODES = ['sprint', 'pomodoro', 'deep_work', 'flow', 'custom'];
      const safeMode = VALID_MODES.includes(mode) ? mode : 'custom';
      try {
        await presence.startSession(roomId, user.id, { task, mode: safeMode, durationSecs });
        io.to(`room:${roomId}`).emit('participant_update', {
          roomId,
          userId: user.id,
          patch: { session: { task, mode: safeMode, secondsRemaining: durationSecs, running: true } },
        });
      } catch (e) {
        console.error('[set_session] failed', { roomId, userId: user.id, mode: safeMode }, e);
      }
    });

    socket.on('timer_control', async ({ roomId, action }: { roomId: string; action: 'pause' | 'resume' | 'end' }) => {
      const s = await presence.timerControl(roomId, user.id, action);
      io.to(`room:${roomId}`).emit('timer_tick', {
        roomId,
        userId: user.id,
        secondsRemaining: s.secondsRemaining,
        running: s.running,
      });
      if (action === 'end') {
        await pushNotification(user.id, 'session_complete', { roomId });
      }
    });

    // ── Ambience (label broadcast; never touches the audio track) ──
    socket.on('set_ambience', async ({ roomId, ambience }: { roomId: string; ambience: string }) => {
      await presence.setRoomAmbience(roomId, ambience);
      io.to(`room:${roomId}`).emit('ambience_changed', { roomId, ambience, changedBy: user.id });
    });

    // ════════════ FEED REACTIONS (live) ════════════
    socket.on('new_reaction', async ({ postId, kind }: { postId: string; kind: ReactionKind }) => {
      const { counts, active } = await toggleReaction(postId, user.id, kind);
      io.to(`post:${postId}`).emit('reaction_update', { postId, kind, counts, actorId: user.id, active });
    });
    socket.on('watch_post', ({ postId }: { postId: string }) => socket.join(`post:${postId}`));
    socket.on('unwatch_post', ({ postId }: { postId: string }) => socket.leave(`post:${postId}`));

    // ════════════ CHAT ════════════
    // ack-style join so the client KNOWS it is subscribed before it relies on
    // live delivery. Membership is enforced here - a stray/forged convo id can
    // never join you to a room you don't belong to (root of "couldn't open chat"
    // when a stale/null id was navigated to).
    socket.on(
      'open_conversation',
      async ({ conversationId }: { conversationId: string }, ack?: (r: unknown) => void) => {
        if (!conversationId) return ack?.({ ok: false, error: 'missing conversationId' });
        if (!(await isMember(conversationId, user.id))) {
          return ack?.({ ok: false, error: 'not a member' });
        }
        socket.join(`convo:${conversationId}`);
        ack?.({ ok: true });
      },
    );

    socket.on(
      'send_message',
      async (
        payload: {
          conversationId: string;
          body?: string;
          clientTempId: string;
          kind?: MessageKind;
          mediaUrl?: string | null;
          mediaMeta?: MediaMeta | null;
          replyToId?: string | null;
        },
        ack?: (r: unknown) => void,
      ) => {
        const { conversationId, body = '', clientTempId, kind = 'text', mediaUrl, mediaMeta, replyToId } = payload;
        try {
          if (!conversationId || !clientTempId) throw new Error('bad payload');
          if (!(await isMember(conversationId, user.id))) throw new Error('not a member');
          const message = await persistMessage({
            conversationId,
            senderId: user.id,
            body,
            kind,
            mediaUrl: mediaUrl ?? null,
            mediaMeta: mediaMeta ?? null,
            clientTempId,
            replyToId: replyToId ?? null,
          });
          // Broadcast to everyone in the convo (the sender too - they reconcile
          // the optimistic bubble by clientTempId / server id).
          io.to(`convo:${conversationId}`).emit('message_new', { conversationId, message, clientTempId });
          // Also push to each other member's PERSONAL room so it lands instantly
          // even if they never joined the convo room (sitting on the chat list,
          // or a missed open_conversation). The client dedups by message id, so
          // a member who IS in the convo room just ignores the duplicate. This
          // is what makes delivery feel instant (Instagram-style) rather than
          // only showing up after reopening the chat.
          const others = await otherMemberIds(conversationId, user.id);
          for (const uid of others) {
            io.to(`user:${uid}`).emit('message_new', { conversationId, message, clientTempId });
          }
          ack?.({ ok: true, message });
          const preview = kind === 'text' ? body.slice(0, 80) : kind === 'image' ? '📷 Photo' : '📎 File';
          await fanoutChatPush(conversationId, user.id, preview);
        } catch (e) {
          ack?.({ ok: false, clientTempId, error: (e as Error).message });
        }
      },
    );

    socket.on('typing', ({ conversationId, isTyping }: { conversationId: string; isTyping: boolean }) => {
      if (!conversationId) return;
      socket.to(`convo:${conversationId}`).emit('typing', {
        conversationId,
        userId: user.id,
        name: user.displayName,
        isTyping,
      });
    });

    // ════════════ DISCONNECT ════════════
    socket.on('disconnect', async () => {
      await presence.handleDisconnect(socket.id, user.id, [...socket.data.rooms]);
    });
  });
}
