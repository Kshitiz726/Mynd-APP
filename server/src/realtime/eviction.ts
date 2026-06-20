/**
 * Grace-period eviction timers. When a socket drops we don't remove the user
 * from the room immediately — we hold a timer so a 5-second subway-tunnel drop
 * doesn't flicker the participant grid. A reconnect cancels it.
 *
 * These live in-process. That's fine: the Redis TTL on the participant hash
 * (see presence.join → `expire 120`) is the durable backstop if this node dies
 * before the timer fires, so no ghost can outlive 2 minutes regardless.
 */
const timers = new Map<string, NodeJS.Timeout>();

const key = (roomId: string, userId: string) => `${roomId}:${userId}`;

export function scheduleEviction(
  roomId: string,
  userId: string,
  delayMs: number,
  run: () => Promise<void>,
) {
  cancelEviction(roomId, userId);
  timers.set(
    key(roomId, userId),
    setTimeout(() => {
      timers.delete(key(roomId, userId));
      run().catch((e) => console.error('eviction failed', e));
    }, delayMs),
  );
}

export function cancelEviction(roomId: string, userId: string) {
  const t = timers.get(key(roomId, userId));
  if (t) {
    clearTimeout(t);
    timers.delete(key(roomId, userId));
  }
}
