// Invite everyone in beta_testers.txt as INTERNAL TestFlight testers.
//
// Internal testers must be App Store Connect *users* on the team - that is the
// trade Apple makes: internal builds skip Beta App Review and are available
// within minutes of processing, but the tester is a team member rather than
// just an email address.
//
// So each person is invited with the least privilege that still works:
//   role                MARKETING  - eligible for TestFlight, and unlike
//                                   DEVELOPER cannot touch signing certificates
//                                   or upload builds.
//   provisioningAllowed false      - no access to certificates or profiles.
//   allAppsVisible      false      - sees OurMynd only, not the whole account.
//
// Two steps, and the second cannot be rushed: an invited person is not a user
// until they accept the email. Only then can they be attached to the internal
// beta group. Re-running this after they accept finishes the job.
import { readFileSync } from 'node:fs';

const ISSUER = process.env.ASC_ISSUER_ID;
const APP_ID = process.env.APP_ID || '6802791162';
const GROUP = process.env.INTERNAL_GROUP || 'Internal Testers';
const DRY_RUN = process.env.DRY_RUN === '1';
const ROLE = process.env.ROLE || 'MARKETING';

const { api } = await import('./asc.mjs');

function parseTesters(path) {
  return readFileSync(path, 'utf8')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .map((l) => {
      const m = l.match(/^(.*?)[-–]\s*([^\s@]+@[^\s@]+\.[^\s@]+)\s*$/);
      if (!m) return null;
      const first = m[1].trim() || m[2].split('@')[0];
      return { firstName: first, lastName: first, email: m[2].trim() };
    })
    .filter(Boolean);
}

const testers = parseTesters(process.env.TESTERS_FILE || '../beta_testers.txt');
console.log(`[internal] ${testers.length} people from the list, role=${ROLE}\n`);

if (DRY_RUN) {
  for (const t of testers) console.log(`  would invite  ${t.email}`);
  console.log('\n[internal] DRY_RUN=1 - nothing sent.');
  process.exit(0);
}
if (!ISSUER) { console.error('ASC_ISSUER_ID not set'); process.exit(1); }

// Who is already a user, and who is already invited?
const users = await api('/v1/users?limit=200');
const invites = await api('/v1/userInvitations?limit=200');
const isUser = new Map((users.body.data || []).map((u) => [u.attributes.username.toLowerCase(), u]));
const isInvited = new Set((invites.body.data || []).map((i) => i.attributes.email.toLowerCase()));

// The internal group to attach accepted users to.
const groups = await api(`/v1/apps/${APP_ID}/betaGroups?limit=200`);
const group = (groups.body.data || []).find((g) => g.attributes.name === GROUP);
if (!group) { console.error(`no beta group named "${GROUP}"`); process.exit(1); }
console.log(`[internal] group "${GROUP}" (${group.id}), internal=${group.attributes.isInternalGroup}\n`);

let invited = 0, attached = 0, pending = 0;
const failed = [];

for (const t of testers) {
  const email = t.email.toLowerCase();

  if (!isUser.has(email) && !isInvited.has(email)) {
    const r = await api('/v1/userInvitations', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'userInvitations',
          attributes: {
            email: t.email,
            firstName: t.firstName,
            lastName: t.lastName,
            roles: [ROLE],
            allAppsVisible: false,
            provisioningAllowed: false,
          },
          relationships: { visibleApps: { data: [{ type: 'apps', id: APP_ID }] } },
        },
      }),
    });
    if (!r.ok) { console.error(`  FAILED   ${t.email} -> ${r.status} ${JSON.stringify(r.body).slice(0, 200)}`); failed.push(t.email); continue; }
    console.log(`  invited  ${t.email}  (must accept the email before they can test)`);
    invited++;
    pending++;
    continue;
  }

  if (isInvited.has(email) && !isUser.has(email)) {
    console.log(`  pending  ${t.email}  (invitation sent earlier, not accepted yet)`);
    pending++;
    continue;
  }

  // Already a team member: attach to the internal group so they get builds.
  const bt = await api(`/v1/betaTesters?filter[email]=${encodeURIComponent(t.email)}&limit=1`);
  const existing = bt.body.data?.[0];
  if (existing) {
    const r = await api(`/v1/betaGroups/${group.id}/relationships/betaTesters`, {
      method: 'POST',
      body: JSON.stringify({ data: [{ type: 'betaTesters', id: existing.id }] }),
    });
    if (r.ok || /already/i.test(JSON.stringify(r.body))) {
      console.log(`  member   ${t.email} -> in "${GROUP}"`);
      attached++;
    } else {
      console.error(`  FAILED   ${t.email} (attach) -> ${r.status} ${JSON.stringify(r.body).slice(0, 200)}`);
      failed.push(t.email);
    }
  } else {
    console.log(`  member   ${t.email} (team user; Apple adds internal testers to the group in App Store Connect)`);
    attached++;
  }
}

console.log(`\n[internal] invited ${invited}, already members ${attached}, awaiting acceptance ${pending}, failed ${failed.length}`);
if (failed.length) { console.log('[internal] failed:', failed.join(', ')); process.exitCode = 1; }
console.log('[internal] Internal builds skip Beta App Review - available minutes after processing.');
