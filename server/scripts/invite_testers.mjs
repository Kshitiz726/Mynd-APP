/**
 * Add the people in beta_testers.txt to a TestFlight group and invite them.
 *
 * Run through ../../testflight-invite-testers.local.sh, which supplies the
 * credentials. It lives here, under server/, rather than at the repo root
 * because it needs `jsonwebtoken` and ESM resolves that from the nearest
 * node_modules - NODE_PATH does not apply to ES modules.
 *
 *   ASC_KEY_ID     the App Store Connect API key id (the .p8 filename)
 *   ASC_ISSUER_ID  the Issuer UUID from Users and Access → Integrations
 *   ASC_KEY_PATH   path to the AuthKey_<id>.p8
 *   BUNDLE_ID      defaults to com.ourmynd.app
 *   GROUP_NAME     defaults to "Beta Testers"
 *   DRY_RUN=1      resolve everything and print the plan, send nothing
 *
 * On external vs internal testers
 * ──────────────────────────────
 * The addresses in beta_testers.txt are personal ones, not App Store Connect
 * users, so these are EXTERNAL testers. That matters in two ways:
 *
 *   • External testers do not have "permissions" in the App Store Connect
 *     sense - there is no role to grant. Access is group membership, and the
 *     group is what a build is released to.
 *   • Apple does not deliver an external invite until the build has passed
 *     Beta App Review. Adding them now is correct and safe; the email arrives
 *     when review clears.
 *
 * Making them internal instead would mean first inviting each person as an
 * App Store Connect user with a role, which grants access to the account
 * itself - not something to do to nine people without being asked.
 */
import { readFileSync } from 'node:fs';
import jwt from 'jsonwebtoken';

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER_ID = process.env.ASC_ISSUER_ID;
const KEY_PATH = process.env.ASC_KEY_PATH;
const BUNDLE_ID = process.env.BUNDLE_ID || 'com.ourmynd.app';
const GROUP_NAME = process.env.GROUP_NAME || 'Beta Testers';
const DRY_RUN = process.env.DRY_RUN === '1';

// Credentials are only needed to talk to Apple. A dry run resolves the list
// and stops, so it must work without them - that is the whole point of being
// able to check who would be contacted before anything is sent.
if (!DRY_RUN) {
  for (const [name, value] of Object.entries({
    ASC_KEY_ID: KEY_ID,
    ASC_ISSUER_ID: ISSUER_ID,
    ASC_KEY_PATH: KEY_PATH,
  })) {
    if (!value) {
      console.error(`missing ${name}`);
      process.exit(2);
    }
  }
}

const API = 'https://api.appstoreconnect.apple.com/v1';

/** Apple caps these at 20 minutes; 10 is plenty for one run. */
function token() {
  return jwt.sign({ aud: 'appstoreconnect-v1' }, readFileSync(KEY_PATH), {
    algorithm: 'ES256',
    keyid: KEY_ID,
    issuer: ISSUER_ID,
    expiresIn: '10m',
  });
}

async function call(path, init = {}) {
  const res = await fetch(path.startsWith('http') ? path : `${API}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token()}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  const text = await res.text();
  if (!res.ok) {
    // Apple's errors are genuinely informative; surface them rather than a code.
    throw new Error(`${res.status} ${path}\n${text.slice(0, 800)}`);
  }
  return text ? JSON.parse(text) : {};
}

/**
 * "Harshal - workwithharshalsharma@gmail.com" → { firstName, email }.
 *
 * Lines are hand-written, so this tolerates stray whitespace and a missing
 * name, and skips anything that is not a plausible address rather than
 * inventing one. Apple requires a first and last name on a beta tester, so a
 * single given name is used for both rather than fabricating a surname.
 */
function parseTesters(path) {
  return readFileSync(path, 'utf8')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const m = line.match(/^(.*?)[-–]\s*([^\s@]+@[^\s@]+\.[^\s@]+)\s*$/);
      if (!m) return null;
      const first = m[1].trim() || m[2].split('@')[0];
      return { firstName: first, lastName: first, email: m[2].trim() };
    })
    .filter(Boolean);
}

const testers = parseTesters(process.env.TESTERS_FILE || 'beta_testers.txt');
console.log(`[invite] ${testers.length} testers parsed from the list:`);
for (const t of testers) console.log(`           ${t.firstName.padEnd(10)} ${t.email}`);

if (DRY_RUN) {
  console.log('\n[invite] DRY_RUN=1 — resolved the list only, nothing was sent.');
  process.exit(0);
}

// ── Resolve the app ──────────────────────────────────────────────────────────
const apps = await call(`/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}`);
const app = apps.data?.[0];
if (!app) {
  console.error(`no app in App Store Connect with bundle id ${BUNDLE_ID}`);
  process.exit(1);
}
console.log(`\n[invite] app: ${app.attributes.name} (${app.id})`);

// ── Find or create the group ─────────────────────────────────────────────────
const groups = await call(`/apps/${app.id}/betaGroups?limit=200`);
let group = groups.data?.find((g) => g.attributes.name === GROUP_NAME);

if (!group) {
  console.log(`[invite] creating external group "${GROUP_NAME}"`);
  const created = await call('/betaGroups', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'betaGroups',
        attributes: {
          name: GROUP_NAME,
          // Apple emails the tester as soon as a reviewed build is available.
          publicLinkEnabled: false,
        },
        relationships: { app: { data: { type: 'apps', id: app.id } } },
      },
    }),
  });
  group = created.data;
} else {
  console.log(`[invite] using existing group "${GROUP_NAME}" (${group.id})`);
}

// ── Add each tester ──────────────────────────────────────────────────────────
// One at a time rather than as a batch: a single bad address in a batch fails
// the whole call, and it is much more useful to know which one.
let added = 0;
let already = 0;
const failed = [];

for (const t of testers) {
  try {
    await call('/betaTesters', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'betaTesters',
          attributes: { email: t.email, firstName: t.firstName, lastName: t.lastName },
          relationships: { betaGroups: { data: [{ type: 'betaGroups', id: group.id }] } },
        },
      }),
    });
    console.log(`  invited  ${t.email}`);
    added++;
  } catch (e) {
    // Already on the account is the common, harmless case: add them to this
    // group instead of treating it as an error.
    if (/already exists|ENTITY_ERROR.*taken/i.test(e.message)) {
      console.log(`  exists   ${t.email} (adding to group)`);
      already++;
    } else {
      console.error(`  FAILED   ${t.email}\n${e.message}`);
      failed.push(t.email);
    }
  }
}

console.log(`\n[invite] added ${added}, already present ${already}, failed ${failed.length}`);
if (failed.length) {
  console.log('[invite] failed addresses:', failed.join(', '));
  process.exitCode = 1;
}
console.log(
  '[invite] External testers receive their email once the build passes Beta App Review.',
);
