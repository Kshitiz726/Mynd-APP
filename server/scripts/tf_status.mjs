// Did the build actually reach anyone?
//
// "Uploaded" answers almost nothing. A build can be VALID in App Store Connect
// and still be installable by nobody, and a tester who never accepted their
// invite is notified of nothing no matter what you ship. This prints the two
// fields that decide it.
//
// Note internalBuildState, not the betaGroups relationship: an internal group
// distributes automatically and that relationship reads empty even for builds
// testers demonstrably have installed. Reading it was misleading once already.
//
// Usage: ASC_ISSUER_ID=… node server/scripts/tf_status.mjs
import { api } from './asc.mjs';

const apps = await api('/v1/apps?limit=10');
const app = apps.body?.data?.find(a => a.attributes?.bundleId === 'com.ourmynd.app');
if (!app) throw new Error('com.ourmynd.app not found on this account');

const builds = await api(`/v1/builds?filter[app]=${app.id}&limit=3&sort=-version`);
for (const b of builds.body.data ?? []) {
  const d = await api(`/v1/builds/${b.id}/buildBetaDetail`);
  const a = d.body?.data?.attributes ?? {};
  console.log(
    `build ${b.attributes.version}  processing=${b.attributes.processingState}  ` +
    `internal=${a.internalBuildState}  external=${a.externalBuildState}  notify=${a.autoNotifyEnabled}`,
  );
}

const groups = await api(`/v1/betaGroups?filter[app]=${app.id}&limit=20`);
for (const g of groups.body.data ?? []) {
  const testers = await api(`/v1/betaTesters?filter[betaGroups]=${g.id}&limit=200`);
  const states = {};
  for (const t of testers.body.data ?? []) {
    const s = t.attributes.state ?? 'UNKNOWN';
    states[s] = (states[s] ?? 0) + 1;
  }
  // INVITED means the invite was never accepted: those people are not testing
  // and will not be notified of anything.
  console.log(`group "${g.attributes.name}" internal=${g.attributes.isInternalGroup} ${JSON.stringify(states)}`);
}
