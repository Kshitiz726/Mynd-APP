import { Redis } from 'ioredis';
import { config } from './config.js';
import { MemoryRedis } from './store/memoryRedis.js';

// When REDIS_URL is set → real cloud Redis (+ Socket.IO Redis adapter for
// multi-node fanout). When absent → in-memory dev shim, single node. The shim
// implements the subset of commands presence.ts uses; we cast to Redis so the
// rest of the codebase stays untouched.
function make(): Redis {
  return (
    config.hasRedis ? new Redis(config.redisUrl, { maxRetriesPerRequest: null }) : new MemoryRedis()
  ) as unknown as Redis;
}

export const redis = make();
export const pubClient = make();
export const subClient = config.hasRedis ? pubClient.duplicate() : make();
export const hasRedis = config.hasRedis;
