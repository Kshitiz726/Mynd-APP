/**
 * Full local stack with ZERO external services or signups:
 *   embedded PostgreSQL (real binary) + the OurMynd server, migrated + seeded.
 *
 * This is the "make it function completely" path. The same server code talks to
 * Supabase in prod — only DATABASE_URL changes. Run: npm run dev:full
 */
import EmbeddedPostgres from 'embedded-postgres';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const PG_PORT = 5433;
const PG_USER = 'postgres';
const PG_PASS = 'postgres';
const PG_DB = 'ourmynd';

async function main() {
  const pg = new EmbeddedPostgres({
    databaseDir: join(root, '.pgdata'),
    user: PG_USER,
    password: PG_PASS,
    port: PG_PORT,
    persistent: true,
    // Force UTF-8 so 'Café Study Room' et al. store correctly (the host locale
    // would otherwise default the cluster to WIN1252).
    initdbFlags: ['--encoding=UTF8', '--no-locale'],
  });

  // initialise() is a no-op if the data dir already exists.
  try {
    await pg.initialise();
  } catch {
    /* already initialised */
  }
  await pg.start();
  console.log(`[devstack] embedded Postgres up on :${PG_PORT}`);

  // Ensure the app database exists (createDatabase throws if present → ignore).
  try {
    await pg.createDatabase(PG_DB);
  } catch {
    /* exists */
  }

  const url = `postgresql://${PG_USER}:${PG_PASS}@localhost:${PG_PORT}/${PG_DB}`;
  process.env.DATABASE_URL = url;
  process.env.JWT_SECRET ??= 'dev-insecure-secret-change-me';
  process.env.NODE_ENV = 'development';

  // Apply schema + dev seed through the app's own db layer. Importing db.js now
  // (after DATABASE_URL is set) makes config resolve hasDb = true. Multi-
  // statement SQL runs via the simple protocol (no params).
  const { db } = await import('../src/db.js');
  const { readdirSync } = await import('node:fs');
  const migDir = join(root, 'supabase/migrations');
  for (const f of readdirSync(migDir).filter((f) => f.endsWith('.sql')).sort()) {
    await db.none(readFileSync(join(migDir, f), 'utf8'));
  }
  await db.none(readFileSync(join(root, 'supabase/seed_dev.sql'), 'utf8'));
  console.log('[devstack] schema + seed applied');

  // Start the server (config already resolved with DATABASE_URL → hasDb = true).
  await import('../src/server.js');

  const shutdown = async () => {
    console.log('\n[devstack] stopping Postgres…');
    await pg.stop();
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((e) => {
  console.error('[devstack] failed:', e);
  process.exit(1);
});
