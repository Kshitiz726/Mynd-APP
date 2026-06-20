/**
 * Realtime smoke test — proves the Focus Room layer works end-to-end with no
 * cloud creds. Two clients connect, both join a room, one starts a 5s timer;
 * we assert presence, the timer tick, and clean disconnect eviction.
 *
 * Run (with the dev server already listening on :8080):
 *   node --import tsx scripts/smoke.ts
 */
import { io, type Socket } from 'socket.io-client';
import jwt from 'jsonwebtoken';

const URL = process.env.SMOKE_URL ?? 'http://localhost:8080';
const SECRET = process.env.JWT_SECRET ?? 'dev-insecure-secret-change-me';
const ROOM = 'cafe-study';

const devToken = (sub: string, name: string, color: string) =>
  jwt.sign({ sub, name, color }, SECRET, { expiresIn: '1h' });

function connect(sub: string, name: string, color: string): Socket {
  return io(URL, { transports: ['websocket'], auth: { token: devToken(sub, name, color) } });
}

const log = (tag: string, obj: unknown) => console.log(`  ${tag}:`, JSON.stringify(obj));
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function main() {
  let passed = 0;
  const expect = (cond: boolean, msg: string) => {
    console.log(`${cond ? '✅' : '❌'} ${msg}`);
    if (cond) passed++;
    else process.exitCode = 1;
  };

  const maya = connect('u-maya', 'Maya', '#4F46E5');
  const leo = connect('u-leo', 'Leo', '#DB2777');

  await Promise.all([
    new Promise((r) => maya.on('connect', r)),
    new Promise((r) => leo.on('connect', r)),
  ]);
  expect(maya.connected && leo.connected, 'both clients authenticated + connected (dev JWT)');

  // Maya joins first; capture her room_state snapshot.
  const mayaState: any = await new Promise((resolve) => {
    maya.on('room_state', resolve);
    maya.emit('join_room', { roomId: ROOM });
  });
  log('room_state', mayaState);
  expect(mayaState.participantCount === 1, 'room_state shows 1 participant after first join');

  // Leo joins; Maya should receive participant_joined with count=2.
  const joined: any = await new Promise((resolve) => {
    maya.on('participant_joined', resolve);
    leo.emit('join_room', { roomId: ROOM });
  });
  log('participant_joined', joined);
  expect(joined.count === 2, 'participant_joined broadcast shows count=2');
  expect(joined.participant.displayName === 'Leo', 'joiner identity (Leo) propagated');

  // Maya starts a 5-second focus session; Leo should see the session in his grid.
  const sessionUpdate: any = await new Promise((resolve) => {
    leo.on('participant_update', (d: any) => {
      if (d.userId === 'u-maya' && d.patch.session) resolve(d);
    });
    maya.emit('set_session', { roomId: ROOM, task: 'Finish quarterly report', mode: 'pomodoro', durationSecs: 5 });
  });
  log('participant_update(session)', sessionUpdate);
  expect(sessionUpdate.patch.session.task === 'Finish quarterly report', 'task synced to other participant');
  expect(sessionUpdate.patch.session.secondsRemaining === 5, 'duration synced (5s)');

  // "Need help" state broadcast.
  const helpUpdate: any = await new Promise((resolve) => {
    leo.on('participant_update', (d: any) => {
      if (d.userId === 'u-maya' && d.patch.state === 'need_help') resolve(d);
    });
    maya.emit('set_state', { roomId: ROOM, state: 'need_help' });
  });
  log('participant_update(need_help)', helpUpdate);
  expect(helpUpdate.patch.state === 'need_help', '"Need Help" state broadcast');

  // Timer authority: pause and read back remaining seconds.
  const tick: any = await new Promise((resolve) => {
    maya.on('timer_tick', resolve);
    maya.emit('timer_control', { roomId: ROOM, action: 'pause' });
  });
  log('timer_tick(pause)', tick);
  expect(tick.running === false && tick.secondsRemaining <= 5, 'server is timer authority (pause → running=false)');

  // Disconnect eviction: Leo drops; Maya sees him go inactive (grace), then left.
  const inactive: Promise<any> = new Promise((resolve) => {
    maya.on('participant_update', (d: any) => {
      if (d.userId === 'u-leo' && d.patch.state === 'inactive') resolve(d);
    });
  });
  leo.close();
  const inact = await inactive;
  log('participant_update(inactive)', inact);
  expect(inact.patch.state === 'inactive', 'dropped peer greyed as inactive (30s grace period)');

  await wait(500);
  maya.close();
  console.log(`\n${passed} realtime checks passed`);
  process.exit(process.exitCode ?? 0);
}

main().catch((e) => {
  console.error('smoke test error:', e);
  process.exit(1);
});
