/**
 * Tiny in-memory stand-in for the subset of ioredis commands that presence.ts
 * uses. Lets the server boot and run the realtime layer (presence, timers,
 * room counts) with no Redis instance, for single-node local dev. Not for prod
 * - it holds no cross-node state and clears on restart.
 */
type Timer = ReturnType<typeof setTimeout>;

export class MemoryRedis {
  private store = new Map<string, unknown>();
  private timers = new Map<string, Timer>();

  async sadd(key: string, ...members: string[]) {
    let s = this.store.get(key);
    if (!(s instanceof Set)) {
      s = new Set<string>();
      this.store.set(key, s);
    }
    let added = 0;
    for (const m of members) if (!(s as Set<string>).has(m)) (s as Set<string>).add(m), added++;
    return added;
  }
  async srem(key: string, ...members: string[]) {
    const s = this.store.get(key);
    if (!(s instanceof Set)) return 0;
    let n = 0;
    for (const m of members) if (s.delete(m)) n++;
    return n;
  }
  async smembers(key: string) {
    const s = this.store.get(key);
    return s instanceof Set ? [...s] : [];
  }
  async scard(key: string) {
    const s = this.store.get(key);
    return s instanceof Set ? s.size : 0;
  }
  async sismember(key: string, m: string) {
    const s = this.store.get(key);
    return s instanceof Set && s.has(m) ? 1 : 0;
  }

  async hset(key: string, a: Record<string, unknown> | string, b?: unknown) {
    let h = this.store.get(key);
    if (!(h instanceof Map)) {
      h = new Map<string, string>();
      this.store.set(key, h);
    }
    const map = h as Map<string, string>;
    if (typeof a === 'object') for (const k of Object.keys(a)) map.set(k, String(a[k]));
    else map.set(a, String(b));
    return 1;
  }
  async hget(key: string, field: string) {
    const h = this.store.get(key);
    return h instanceof Map ? (h.get(field) ?? null) : null;
  }
  async hgetall(key: string) {
    const h = this.store.get(key);
    return h instanceof Map ? Object.fromEntries(h) : {};
  }

  async get(key: string) {
    const v = this.store.get(key);
    return typeof v === 'string' ? v : null;
  }
  async set(key: string, value: string) {
    this.store.set(key, String(value));
    return 'OK';
  }
  async del(...keys: string[]) {
    let n = 0;
    for (const k of keys) {
      if (this.store.delete(k)) n++;
      this.clearTimer(k);
    }
    return n;
  }
  async exists(key: string) {
    return this.store.has(key) ? 1 : 0;
  }
  async expire(key: string, seconds: number) {
    if (!this.store.has(key)) return 0;
    this.clearTimer(key);
    this.timers.set(
      key,
      setTimeout(() => {
        this.store.delete(key);
        this.timers.delete(key);
      }, seconds * 1000),
    );
    return 1;
  }
  private clearTimer(key: string) {
    const t = this.timers.get(key);
    if (t) {
      clearTimeout(t);
      this.timers.delete(key);
    }
  }

  multi() {
    return new MemoryChain(this);
  }
  pipeline() {
    return new MemoryChain(this);
  }
  duplicate() {
    return this;
  }
  // ioredis emits connection events; no-op them so callers can attach handlers.
  on() {
    return this;
  }
}

/** Chainable multi()/pipeline() that runs queued ops on exec(), ioredis-style. */
class MemoryChain {
  private ops: Array<[string, unknown[]]> = [];
  constructor(private r: MemoryRedis) {}
  private q(name: string, args: unknown[]) {
    this.ops.push([name, args]);
    return this;
  }
  sadd(...a: unknown[]) { return this.q('sadd', a); }
  srem(...a: unknown[]) { return this.q('srem', a); }
  hset(...a: unknown[]) { return this.q('hset', a); }
  hgetall(...a: unknown[]) { return this.q('hgetall', a); }
  scard(...a: unknown[]) { return this.q('scard', a); }
  expire(...a: unknown[]) { return this.q('expire', a); }
  del(...a: unknown[]) { return this.q('del', a); }
  set(...a: unknown[]) { return this.q('set', a); }
  async exec(): Promise<Array<[Error | null, unknown]>> {
    const res: Array<[Error | null, unknown]> = [];
    for (const [m, a] of this.ops) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const v = await (this.r as any)[m](...a);
      res.push([null, v]);
    }
    return res;
  }
}
