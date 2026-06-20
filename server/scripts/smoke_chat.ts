// Quick chat smoke: token → group convo → socket connect → open → send.
// Run while the server is up: node --import tsx scripts/smoke_chat.ts
import { io } from 'socket.io-client';

const BASE = 'http://localhost:8080';

async function main() {
  const tok = await (await fetch(`${BASE}/api/dev/token?user=sam`)).json();
  const groups = await (await fetch(`${BASE}/api/groups`, {
    headers: { authorization: `Bearer ${tok.token}` },
  })).json();
  const g = groups.groups[0];
  const conv = await (await fetch(`${BASE}/api/groups/${g.id}/conversation`, {
    headers: { authorization: `Bearer ${tok.token}` },
  })).json();
  console.log('group', g.name, 'convo', conv.conversationId);

  const socket = io(BASE, { transports: ['websocket'], auth: { token: tok.token } });

  socket.on('connect', () => console.log('✅ socket connected', socket.id));
  socket.on('connect_error', (e) => console.log('❌ connect_error', e.message));
  socket.on('message_new', (d) => console.log('📨 message_new', d.message?.body, 'temp', d.clientTempId));

  socket.on('connect', () => {
    socket.emit('open_conversation', { conversationId: conv.conversationId }, (ack: unknown) => {
      console.log('open ack:', ack);
      const tempId = 'tmp_smoke_' + Date.now();
      socket.emit(
        'send_message',
        { conversationId: conv.conversationId, clientTempId: tempId, body: 'smoke hi' },
        (ack2: unknown) => console.log('send ack:', ack2),
      );
    });
  });

  setTimeout(() => {
    console.log('done');
    process.exit(0);
  }, 4000);
}
main();
