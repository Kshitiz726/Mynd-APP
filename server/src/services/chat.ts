import { db } from '../db.js';

export type MessageKind = 'text' | 'image' | 'file';

export interface MediaMeta {
  name?: string;
  mime?: string;
  size?: number;
  width?: number;
  height?: number;
}

export interface MessageView {
  id: string;
  conversationId: string;
  senderId: string;
  body: string;
  kind: MessageKind;
  mediaUrl: string | null;
  mediaMeta: MediaMeta | null;
  createdAt: string;
  clientTempId: string | null;
  senderName: string;
  senderInitial: string;
  senderColor: string | null;
  replyToId: string | null;
  replyToBody: string | null;
  replyToSender: string | null;
}

export interface PersistInput {
  conversationId: string;
  senderId: string;
  body?: string;
  kind?: MessageKind;
  mediaUrl?: string | null;
  mediaMeta?: MediaMeta | null;
  clientTempId?: string | null;
  replyToId?: string | null;
}

const SELECT_VIEW = `
  select m.id, m.conversation_id, m.sender_id, m.body, m.kind, m.media_url,
         m.media_meta, m.created_at, m.client_temp_id, m.reply_to_id,
         u.display_name, u.initial, u.avatar_color,
         rm.body as reply_to_body, ru.display_name as reply_to_sender
  from messages m
  join users u on u.id = m.sender_id
  left join messages rm on rm.id = m.reply_to_id
  left join users ru on ru.id = rm.sender_id`;

function toView(m: any): MessageView {
  return {
    id: m.id,
    conversationId: m.conversation_id,
    senderId: m.sender_id,
    body: m.body,
    kind: m.kind,
    mediaUrl: m.media_url ?? null,
    mediaMeta: m.media_meta ?? null,
    createdAt: m.created_at,
    clientTempId: m.client_temp_id ?? null,
    senderName: m.display_name,
    senderInitial: m.initial,
    senderColor: m.avatar_color,
    replyToId: m.reply_to_id ?? null,
    replyToBody: m.reply_to_body ?? null,
    replyToSender: m.reply_to_sender ?? null,
  };
}

/**
 * Persist a message idempotently. A retried/duplicated socket frame carrying the
 * same (senderId, clientTempId) returns the already-stored row instead of
 * inserting a second one — this is what makes optimistic sends safe under
 * reconnects and double taps.
 */
export async function persistMessage(input: PersistInput): Promise<MessageView> {
  const {
    conversationId,
    senderId,
    body = '',
    kind = 'text',
    mediaUrl = null,
    mediaMeta = null,
    clientTempId = null,
    replyToId = null,
  } = input;

  // NOTE: a data-modifying CTE's INSERT is NOT visible to a base-table
  // reference in the same statement (MVCC snapshot), so we must read every
  // message column from the INSERT's own RETURNING and join only `users`
  // (which isn't modified here). Joining back to `messages` would match 0 rows.
  const m = await db.one(
    `with ins as (
       insert into messages(conversation_id, sender_id, body, kind, media_url, media_meta, client_temp_id, reply_to_id)
       values($1,$2,$3,$4,$5,$6,$7,$8)
       on conflict (sender_id, client_temp_id) where client_temp_id is not null
         do update set client_temp_id = excluded.client_temp_id
       returning id, conversation_id, sender_id, body, kind, media_url, media_meta, created_at, client_temp_id, reply_to_id
     )
     select ins.*, u.display_name, u.initial, u.avatar_color,
            rm.body as reply_to_body, ru.display_name as reply_to_sender
     from ins 
     join users u on u.id = ins.sender_id
     left join messages rm on rm.id = ins.reply_to_id
     left join users ru on ru.id = rm.sender_id`,
    [conversationId, senderId, body.trim(), kind, mediaUrl, mediaMeta, clientTempId, replyToId],
  );
  return toView(m);
}

/** Every OTHER member of a conversation (used to fan a new message to their
 *  personal socket rooms so delivery is instant even when they haven't joined
 *  the convo room — e.g. sitting on the chat list). */
export async function otherMemberIds(conversationId: string, senderId: string): Promise<string[]> {
  const rows = await db.any<{ user_id: string }>(
    `select user_id from conversation_members where conversation_id=$1 and user_id<>$2`,
    [conversationId, senderId],
  );
  return rows.map((r) => r.user_id);
}

/** Membership check used by every conversation-scoped operation. */
export async function isMember(conversationId: string, userId: string): Promise<boolean> {
  const row = await db.oneOrNone(
    `select 1 from conversation_members where conversation_id=$1 and user_id=$2`,
    [conversationId, userId],
  );
  return !!row;
}

export { SELECT_VIEW, toView };
