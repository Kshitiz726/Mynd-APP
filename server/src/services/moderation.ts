/**
 * Blocking, in one place.
 *
 * Every surface that shows one user's content to another has to ask the same
 * question, and it has to get the same answer. Spreading that across the feed,
 * the comments, chat and presence is how a block ends up working in three
 * places out of four - and the one that leaks is the one a reviewer finds.
 */

/**
 * SQL fragment: true when the caller and [authorColumn] have not blocked each
 * other in either direction.
 *
 * Symmetric on purpose. One-directional blocking hides them from you but leaves
 * you visible to them, which is backwards - the person being blocked is the one
 * you want to stop seeing you. Stored one way, read both ways: storing both
 * directions would double the rows and make unblocking ambiguous.
 *
 * Takes the parameter *names* rather than values so it composes into queries
 * that already number their arguments.
 */
export function notBlockedSql(authorColumn: string, viewerParam: string): string {
  return `not exists (
    select 1 from user_blocks b
    where (b.blocker_id = ${viewerParam} and b.blocked_id = ${authorColumn})
       or (b.blocker_id = ${authorColumn} and b.blocked_id = ${viewerParam})
  )`;
}

/** Every user id [viewerId] cannot see or be seen by, in either direction. */
export const blockedIdsSql = `
  select case when blocker_id = $1 then blocked_id else blocker_id end as id
  from user_blocks
  where blocker_id = $1 or blocked_id = $1`;

/**
 * Whether either of [a] or [b] has blocked the other.
 *
 * Hiding content is only half of what a block means. If somebody can still send
 * you a friend request or open a DM, you have not blocked them - you have
 * muted them, and the next thing they do arrives as a notification. These are
 * the two paths that start contact, so they are the two that have to refuse.
 */
export async function isBlockedBetween(
  db: { oneOrNone: (q: string, v: unknown[]) => Promise<unknown> },
  a: string,
  b: string,
): Promise<boolean> {
  const row = await db.oneOrNone(
    `select 1 from user_blocks
      where (blocker_id=$1 and blocked_id=$2)
         or (blocker_id=$2 and blocked_id=$1)
      limit 1`,
    [a, b],
  );
  return row != null;
}
