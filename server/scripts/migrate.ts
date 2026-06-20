// Applies SQL migrations against the cloud DATABASE_URL (Supabase / RDS).
// Usage: npm run migrate
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { db } from '../src/db.js';

const dir = join(dirname(fileURLToPath(import.meta.url)), '..', 'supabase', 'migrations');

const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
for (const f of files) {
  console.log(`applying ${f}…`);
  await db.none(readFileSync(join(dir, f), 'utf8'));
}
console.log('migrations done');
process.exit(0);
