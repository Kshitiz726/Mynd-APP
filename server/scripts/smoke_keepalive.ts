/**
 * Who keeps themselves awake?
 *
 * The keepalive election decides which server stays warm and which ones Render
 * is allowed to idle out, so getting it wrong costs either a month of instance
 * hours or a cold live server. There is no test runner on this side of the
 * repo, so the ranking rules are exercised here the way the other smoke
 * scripts do it: pure functions, real assertions, non-zero exit on failure.
 *
 *   npm run smoke:keepalive
 */
import assert from 'node:assert/strict';
import { listedServers, rankOf, origin } from '../src/services/keepalive.js';

const PRIMARY = 'https://ourmynd-server-3bvh.onrender.com';
const STANDBY = 'https://ourmynd-server.onrender.com';
const THIRD = 'https://api.ourmynd.com';

let failures = 0;
function check(what: string, run: () => void) {
  try {
    run();
    console.log(`  ok   ${what}`);
  } catch (err) {
    failures++;
    console.error(`  FAIL ${what}`);
    console.error(`       ${(err as Error).message.split('\n')[0]}`);
  }
}

console.log('keepalive election');

check('an address reduces to its bare origin', () => {
  assert.equal(origin('https://Api.OurMynd.com/health?x=1'), 'https://api.ourmynd.com');
  assert.equal(origin('https://api.ourmynd.com/'), 'https://api.ourmynd.com');
});

check('rubbish is not an address', () => {
  for (const junk of [null, undefined, '', '   ', 'not a url', 42, {}]) {
    assert.equal(origin(junk), null, `origin(${JSON.stringify(junk)})`);
  }
});

check('the list is api first, then servers, in file order', () => {
  assert.deepEqual(
    listedServers({ api: PRIMARY, servers: [PRIMARY, STANDBY, THIRD] }),
    [PRIMARY, STANDBY, THIRD],
  );
});

check('a file with only api still gives a list of one', () => {
  assert.deepEqual(listedServers({ api: PRIMARY }), [PRIMARY]);
});

check('a malformed file yields nothing rather than throwing', () => {
  for (const junk of [null, undefined, 'a string', 42, [], { servers: 'nope' }]) {
    assert.deepEqual(listedServers(junk), [], `listedServers(${JSON.stringify(junk)})`);
  }
});

check('the primary/secondary spelling is understood too', () => {
  // The live file is written this way, and an election that read an empty list
  // would leave every server believing it was in charge.
  assert.deepEqual(
    listedServers({ primary: PRIMARY, secondary: STANDBY }),
    [PRIMARY, STANDBY],
  );
});

check('the primary ranks first and so always stays awake', () => {
  const listed = listedServers({ api: PRIMARY, servers: [PRIMARY, STANDBY] });
  assert.equal(rankOf(listed, PRIMARY), 0);
});

check('a standby knows it is below the primary', () => {
  const listed = listedServers({ api: PRIMARY, servers: [PRIMARY, STANDBY] });
  assert.equal(rankOf(listed, STANDBY), 1);
});

check('a server not in the file ranks -1, which means stay awake', () => {
  // The caller reads -1 as "misconfigured, do not put this one to sleep".
  const listed = listedServers({ api: PRIMARY, servers: [PRIMARY, STANDBY] });
  assert.equal(rankOf(listed, 'https://ourmynd-server-k2x9.onrender.com'), -1);
});

check('a trailing slash or odd case does not hide a server from itself', () => {
  // RENDER_EXTERNAL_URL and the file are written by different hands.
  const listed = listedServers({ api: PRIMARY, servers: [PRIMARY, STANDBY] });
  assert.equal(rankOf(listed, `${STANDBY}/`), 1);
  assert.equal(rankOf(listed, STANDBY.toUpperCase().replace('HTTPS', 'https')), 1);
});

check('promotion: with the primary dropped from the file, the standby leads', () => {
  const listed = listedServers({ api: STANDBY, servers: [STANDBY, THIRD] });
  assert.equal(rankOf(listed, STANDBY), 0);
});

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log('\nall checks passed');
