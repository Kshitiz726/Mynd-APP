/**
 * Public focus-room smoke test (Discord-style). Proves:
 *   1. User A creates a PUBLIC room via REST.
 *   2. User B — sitting in the lobby — receives `room_created` live.
 *   3. Both join; counts broadcast to the lobby.
 *   4. A PRIVATE room does NOT appear in B's public list.
 *
 * Run (server already up): node --import tsx scripts/smoke_rooms.ts
 */
import { io, type Socket } from 'socket.io-client';
import jwt from 'jsonwebtoken';

const URL = process.env.SMOKE_URL ?? 'http://localhost:8080';
const SECRET = process.env.JWT_SECRET ?? 'dev-insecure-secret-change-me';
const SAM = '11111111-1111-1111-1111-111111111111';
const LEO = '33333333-3333-3333-3333-333333333333';

const token = (sub: string, name: string) => jwt.sign({ sub, name }, SECRET, { expiresIn: '1h' });
const connect = (sub: string, name: string): Socket =>
  io(URL, { transports: ['websocket'], auth: { token: token(sub, name) } });
const api = async (path: string, sub: string, name: string, body?: unknown) => {
  const res = await fetch(`${URL}${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token(sub, name)}` },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
};

async function main() {
  let passed = 0;
  const expect = (cond: boolean, msg: string) => {
    console.log(`${cond ? '✅' : '❌'} ${msg}`);
    cond ? passed++ : (process.exitCode = 1);
  };

  const leo = connect(LEO, 'Leo'); // the "other user" sitting in the lobby
  await new Promise((r) => leo.on('connect', r));

  // Leo listens for a new public room appearing in his list.
  const createdP = new Promise<any>((resolve) => leo.on('room_created', resolve));

  // Sam creates a PUBLIC room over REST.
  const pub = await api('/api/rooms', SAM, 'Sam', {
    title: 'Late Night Grind', iconName: 'moon', ambience: 'rain', visibility: 'public',
  });
  console.log('  created:', JSON.stringify({ id: pub.id, title: pub.title, visibility: pub.visibility }));
  expect(pub.visibility === 'public', 'public room created via REST');

  const broadcast = await createdP;
  console.log('  room_created received by Leo:', broadcast.title);
  expect(broadcast.id === pub.id, 'Leo received room_created broadcast live (no refresh)');

  // Sam creates a PRIVATE room — Leo should NOT get a broadcast for it.
  let privateLeaked = false;
  leo.on('room_created', (d: any) => { if (d.title === 'Secret Room') privateLeaked = true; });
  const priv = await api('/api/rooms', SAM, 'Sam', { title: 'Secret Room', visibility: 'private' });
  await new Promise((r) => setTimeout(r, 300));
  expect(!privateLeaked, 'private room NOT broadcast to the lobby');

  // Leo's public room list excludes the private room.
  const list = await api('/api/rooms', LEO, 'Leo');
  const ids = list.rooms.map((r: any) => r.id);
  expect(ids.includes(pub.id), 'public room is in everyone\'s list');
  expect(!ids.includes(priv.id), 'private room hidden from other users\' list');

  // Both join the public room → Leo sees the live count climb in his lobby.
  const countP = new Promise<any>((resolve) => {
    let seen = 0;
    leo.on('room_live_update', (d: any) => {
      if (d.roomId === pub.id) { seen = d.count; if (d.count >= 2) resolve(d); }
    });
  });
  const sam = connect(SAM, 'Sam');
  await new Promise((r) => sam.on('connect', r));
  sam.emit('join_room', { roomId: pub.id });
  leo.emit('join_room', { roomId: pub.id });
  const count = await countP;
  console.log('  room_live_update:', JSON.stringify(count));
  expect(count.count === 2, 'live participant count broadcast to lobby (2 joined)');

  sam.close();
  leo.close();
  console.log(`\n${passed} room checks passed`);
  process.exit(process.exitCode ?? 0);
}

main().catch((e) => { console.error('smoke error:', e); process.exit(1); });
