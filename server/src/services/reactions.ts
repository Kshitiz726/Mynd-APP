import { db } from '../db.js';

export type ReactionKind = 'relate' | 'support' | 'proud';

export interface ReactionResult {
  active: boolean; // true → the user now holds this reaction; false → removed
  counts: { relate: number; support: number; proud: number };
}

/**
 * Stateful toggle, shared by the REST fallback and the socket path.
 * Idempotent: delete-then-insert-if-nothing-deleted. The posts.*_count columns
 * are maintained by a Postgres trigger, so we never COUNT(*) the reactions table.
 */
export async function toggleReaction(
  postId: string,
  userId: string,
  kind: ReactionKind,
): Promise<ReactionResult> {
  const removed = await db.result(
    `delete from reactions where post_id=$1 and user_id=$2 and kind=$3`,
    [postId, userId, kind],
  );
  const active = removed.rowCount === 0;
  if (active) {
    await db.none(
      `insert into reactions(post_id, user_id, kind) values($1,$2,$3)
       on conflict do nothing`,
      [postId, userId, kind],
    );
  }
  const c = await db.one(
    `select relate_count, support_count, proud_count from posts where id=$1`,
    [postId],
  );
  return {
    active,
    counts: { relate: c.relate_count, support: c.support_count, proud: c.proud_count },
  };
}
