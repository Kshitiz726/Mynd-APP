import pgPromise from 'pg-promise';
import { config } from './config.js';

const pgp = pgPromise();

// Local/embedded Postgres has no TLS; managed Postgres (Supabase/RDS) requires
// it. Detect by host so the same code runs in dev and prod unchanged.
const isLocal = /localhost|127\.0\.0\.1/.test(config.databaseUrl);

export const db = pgp({
  connectionString: config.databaseUrl,
  ssl: isLocal ? false : { rejectUnauthorized: false },
  max: 20,
});
