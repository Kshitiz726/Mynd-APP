// Hand a build to the internal tester group.
//
// A build can process to VALID and still reach nobody: internalBuildState stays
// READY_FOR_BETA_TESTING until the build is actually attached to a group. That
// is the difference between "uploaded" and "your testers were notified", and it
// is invisible unless you look at this field.
//
// Usage: ASC_ISSUER_ID=… node server/scripts/tf_distribute.mjs [buildVersion]
import { api } from './asc.mjs';

const want = process.argv[2] ?? null;

const apps = await api('/v1/apps?limit=10');
const app = apps.body?.data?.find((a) => a.attributes?.bundleId === 'com.ourmynd.app');
if (!app) throw new Error('com.ourmynd.app not found on this account');

const builds = await api(`/v1/builds?filter[app]=${app.id}&limit=5&sort=-version`);
const build = want
  ? builds.body.data.find((b) => b.attributes.version === want)
  : builds.body.data[0];
if (!build) throw new Error(`build ${want ?? '(latest)'} not found`);
console.log(`build ${build.attributes.version}: processing=${build.attributes.processingState}`);

const groups = await api(`/v1/betaGroups?filter[app]=${app.id}&limit=20`);
for (const g of groups.body.data ?? []) {
  const a = g.attributes ?? {};
  console.log(`group "${a.name}" internal=${a.isInternalGroup} autoNotify=${a.publicLinkEnabled ?? 'n/a'}`);
}

const target = (groups.body.data ?? []).filter((g) => g.attributes?.isInternalGroup);
if (!target.length) throw new Error('no internal group on this app');

for (const g of target) {
  const res = await api(`/v1/betaGroups/${g.id}/relationships/builds`, {
    method: 'POST',
    body: JSON.stringify({ data: [{ type: 'builds', id: build.id }] }),
  });
  console.log(`attach to "${g.attributes.name}": HTTP ${res.status}` +
    (res.ok ? ' ok' : ` -> ${JSON.stringify(res.body).slice(0, 300)}`));
}
