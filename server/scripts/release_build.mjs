/**
 * Wait for a freshly uploaded build to finish processing, give it release
 * notes, and hand it to the TestFlight group so testers are told to update.
 *
 * Uploading an IPA does NOT notify anybody. altool only puts the binary in
 * App Store Connect; a build sitting there is invisible to testers until it
 * is attached to a beta group. That attachment is the notification, which is
 * why this script exists alongside invite_testers.mjs - that one adds people
 * to the group, this one gives the group something to install.
 *
 *   ASC_KEY_ID     the App Store Connect API key id (the .p8 filename)
 *   ASC_ISSUER_ID  the Issuer UUID from Users and Access -> Integrations
 *   ASC_KEY_PATH   path to the AuthKey_<id>.p8
 *   BUILD_VERSION  the CFBundleVersion to release, e.g. 13
 *   BUNDLE_ID      defaults to com.ourmynd.app
 *   GROUP_NAME     defaults to "Beta Testers"
 *   WHATS_NEW      release notes shown in TestFlight
 *
 * On external testers: Apple will not deliver the update to them until the
 * build clears Beta App Review. Attaching it here is what puts it in the
 * queue, so this script finishing is not the same as phones buzzing.
 *
 * Success is confirmed against buildBetaDetail.internalBuildState, never the
 * betaGroups relationship. See the comment at the verification step: that
 * relationship reads empty for internal groups whatever the truth is, and
 * trusting it produced a confident, wrong "your testers were not notified".
 */
import { readFileSync } from 'node:fs';
import jwt from 'jsonwebtoken';

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER_ID = process.env.ASC_ISSUER_ID;
const KEY_PATH = process.env.ASC_KEY_PATH;
const BUNDLE_ID = process.env.BUNDLE_ID || 'com.ourmynd.app';
const GROUP_NAME = process.env.GROUP_NAME || 'Beta Testers';
const BUILD_VERSION = process.env.BUILD_VERSION;
const WHATS_NEW = process.env.WHATS_NEW || 'Bug fixes and improvements.';

for (const [name, value] of Object.entries({
  ASC_KEY_ID: KEY_ID,
  ASC_ISSUER_ID: ISSUER_ID,
  ASC_KEY_PATH: KEY_PATH,
  BUILD_VERSION,
})) {
  if (!value) {
    console.error(`missing ${name}`);
    process.exit(2);
  }
}

const API = 'https://api.appstoreconnect.apple.com/v1';

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
  if (!res.ok) throw new Error(`${res.status} ${path}\n${text.slice(0, 800)}`);
  return text ? JSON.parse(text) : {};
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// -- Resolve the app --------------------------------------------------------
const apps = await call(`/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}`);
const app = apps.data?.[0];
if (!app) {
  console.error(`no app in App Store Connect with bundle id ${BUNDLE_ID}`);
  process.exit(1);
}
console.log(`[release] app: ${app.attributes.name} (${app.id})`);

// -- Wait for the build to appear and finish processing ---------------------
// Apple takes a few minutes to even list a build after altool returns, and
// several more to process it. Neither step reports progress, so this polls.
let build = null;
const deadline = Date.now() + 45 * 60 * 1000;
while (Date.now() < deadline) {
  const builds = await call(
    `/builds?filter[app]=${app.id}&filter[version]=${encodeURIComponent(BUILD_VERSION)}&limit=1`,
  );
  build = builds.data?.[0] ?? null;
  const state = build?.attributes?.processingState;
  if (state === 'VALID') {
    console.log(`[release] build ${BUILD_VERSION} processed (${build.id})`);
    break;
  }
  if (state === 'FAILED' || state === 'INVALID') {
    console.error(`[release] build ${BUILD_VERSION} is ${state}. Stopping.`);
    process.exit(1);
  }
  console.log(`[release] build ${BUILD_VERSION}: ${state ?? 'not listed yet'}, waiting...`);
  await sleep(60_000);
}
if (!build || build.attributes.processingState !== 'VALID') {
  console.error('[release] gave up waiting for processing.');
  process.exit(1);
}

// -- Release notes ----------------------------------------------------------
// This is the text testers actually read in TestFlight, so "update the app"
// has to say what changed or it is just noise in their notification tray.
const locs = await call(`/builds/${build.id}/betaBuildLocalizations`);
const enGb = locs.data?.find((l) => l.attributes.locale?.startsWith('en'));
if (enGb) {
  await call(`/betaBuildLocalizations/${enGb.id}`, {
    method: 'PATCH',
    body: JSON.stringify({
      data: {
        type: 'betaBuildLocalizations',
        id: enGb.id,
        attributes: { whatsNew: WHATS_NEW },
      },
    }),
  });
  console.log('[release] release notes updated');
} else {
  await call('/betaBuildLocalizations', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'betaBuildLocalizations',
        attributes: { locale: 'en-US', whatsNew: WHATS_NEW },
        relationships: { build: { data: { type: 'builds', id: build.id } } },
      },
    }),
  });
  console.log('[release] release notes created');
}

// -- Hand the build to the group. This is the notification. -----------------
const groups = await call(`/apps/${app.id}/betaGroups?limit=200`);
const group = groups.data?.find((g) => g.attributes.name === GROUP_NAME);
if (!group) {
  console.error(`no beta group named "${GROUP_NAME}". Run the invite script first.`);
  process.exit(1);
}

await call(`/betaGroups/${group.id}/relationships/builds`, {
  method: 'POST',
  body: JSON.stringify({ data: [{ type: 'builds', id: build.id }] }),
});

// Read it back rather than trusting the 204, and read the RIGHT field.
//
// Not the betaGroups relationship: for an internal group that reads empty even
// for builds testers demonstrably have installed, so checking it reports a
// failure that did not happen. buildBetaDetail.internalBuildState is what
// actually separates "uploaded" from "your testers can install it":
// READY_FOR_BETA_TESTING means it reached nobody, IN_BETA_TESTING means it did.
//
// Apple needs a moment to flip it, so give it a few tries before believing a
// negative.
let detail = null;
for (let i = 0; i < 6; i++) {
  await sleep(5000);
  const d = await call(`/builds/${build.id}/buildBetaDetail`);
  detail = d.data?.attributes ?? null;
  if (detail?.internalBuildState === 'IN_BETA_TESTING') break;
}

if (detail?.internalBuildState !== 'IN_BETA_TESTING') {
  console.error(
    `[release] FAILED: build ${BUILD_VERSION} is ` +
      `${detail?.internalBuildState ?? 'in an unknown state'}, so testers cannot ` +
      `install it yet. They have NOT been notified.`,
  );
  process.exit(1);
}

console.log(
  `[release] build ${BUILD_VERSION} is IN_BETA_TESTING for "${GROUP_NAME}" (verified)`,
);
if (detail.autoNotifyEnabled === false) {
  console.log(
    '[release] NOTE: autoNotifyEnabled is off for this build, so testers can ' +
      'install it but were not pushed a notification.',
  );
}

const testers = await call(`/betaGroups/${group.id}/betaTesters?limit=200`);
console.log(`[release] ${testers.data?.length ?? 0} testers in that group`);
console.log('[release] external testers are notified once Beta App Review clears.');
