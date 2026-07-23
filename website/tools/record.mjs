/* ===========================================================================
   Record video.html to an mp4, frame by frame.
   ---------------------------------------------------------------------------
   No dependencies. Node 22+ ships a WebSocket client, which is all that is
   needed to speak the Chrome DevTools Protocol directly.

   The trick that makes this exact rather than approximate is CDP virtual time:
   the renderer's clock is paused, then advanced by exactly one frame at a time,
   and timers, transitions and CSS animations all move with it. So the output is
   deterministic - the same run twice is the same file - and it does not matter
   how long a frame takes to encode.

   Frames go straight down a pipe into ffmpeg. Nothing is written to disk except
   the finished film.

   Usage:  node tools/record.mjs [--fps 30] [--out ourmynd.mp4] [--port 4321]
   ======================================================================== */

import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const arg = (name, fallback) => {
  const i = process.argv.indexOf('--' + name);
  return i > -1 ? process.argv[i + 1] : fallback;
};

const FPS = Number(arg('fps', 30));
const OUT = arg('out', 'ourmynd-walkthrough.mp4');
const PORT = Number(arg('port', 4321));
const DEBUG_PORT = Number(arg('debug-port', 9333));
const WIDTH = 1080;
const HEIGHT = 1920;

const CHROME = arg('chrome',
  'C:/Program Files/Google/Chrome/Application/chrome.exe');

/* ---- CCP plumbing -------------------------------------------------------- */
class CDP {
  constructor(ws) {
    this.ws = ws;
    this.id = 0;
    this.pending = new Map();
    this.listeners = new Map();
    ws.addEventListener('message', (e) => {
      const msg = JSON.parse(e.data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
      } else if (msg.method) {
        (this.listeners.get(msg.method) || []).forEach((fn) => fn(msg.params));
      }
    });
  }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }
  on(method, fn) {
    if (!this.listeners.has(method)) this.listeners.set(method, []);
    this.listeners.get(method).push(fn);
  }
  once(method) {
    return new Promise((resolve) => {
      const fn = (p) => {
        const arr = this.listeners.get(method);
        arr.splice(arr.indexOf(fn), 1);
        resolve(p);
      };
      this.on(method, fn);
    });
  }
}

async function connect(url) {
  const ws = new WebSocket(url);
  await new Promise((res, rej) => {
    ws.addEventListener('open', res, { once: true });
    ws.addEventListener('error', rej, { once: true });
  });
  return new CDP(ws);
}

/* ---- go ------------------------------------------------------------------ */
const url = `http://127.0.0.1:${PORT}/video.html`;

console.log('launching chrome...');
const chrome = spawn(CHROME, [
  '--headless=new',
  '--disable-gpu',
  '--hide-scrollbars',
  '--mute-audio',
  '--no-first-run',
  '--force-device-scale-factor=1',
  `--window-size=${WIDTH},${HEIGHT}`,
  `--remote-debugging-port=${DEBUG_PORT}`,
  '--user-data-dir=' + (process.env.TEMP || '/tmp') + '/om-record-profile',
  url,
], { stdio: 'ignore' });

// Wait for the debugger to answer, then find the page target.
let target = null;
for (let i = 0; i < 60 && !target; i++) {
  await sleep(500);
  try {
    const list = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/list`)).json();
    target = list.find((t) => t.type === 'page' && t.url.includes('video.html'));
  } catch { /* not up yet */ }
}
if (!target) { chrome.kill(); throw new Error('chrome never opened the page'); }

const cdp = await connect(target.webSocketDebuggerUrl);
await cdp.send('Page.enable');
await cdp.send('Emulation.setDeviceMetricsOverride', {
  width: WIDTH, height: HEIGHT, deviceScaleFactor: 1, mobile: false,
});

// Let it settle in real time: fonts, the iframe, and the WebGL contexts all
// need to exist before the clock is taken away from them.
console.log('warming up...');
await sleep(6000);

const read = async (expr) =>
  (await cdp.send('Runtime.evaluate', { expression: expr, returnByValue: true })).result.value;

const totalMs = Number(await read('document.documentElement.dataset.filmReady || 0'));
if (!totalMs) { chrome.kill(); throw new Error('video.html never reported a duration'); }

const frameMs = 1000 / FPS;
// 600ms of lead-in before the first cut, plus a beat to rest on the last card.
let frames = Math.ceil((totalMs + 600 + 1200) / frameMs);
// --max-frames exists so the whole pipeline can be smoke-tested in seconds
// rather than in minutes.
const cap = Number(arg('max-frames', 0));
if (cap) frames = Math.min(frames, cap);
console.log(`film is ${(totalMs / 1000).toFixed(1)}s -> ${frames} frames at ${FPS}fps`);

const ff = spawn('ffmpeg', [
  '-y',
  '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '19',
  '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
  OUT,
], { stdio: ['pipe', 'ignore', 'inherit'] });

const write = (buf) => new Promise((res) => {
  if (!ff.stdin.write(buf)) ff.stdin.once('drain', res);
  else res();
});

// Pause the world, and only then start the film. Warming up in real time
// would otherwise burn the first few seconds of it before frame one.
await cdp.send('Emulation.setVirtualTimePolicy', { policy: 'pause' });
await cdp.send('Runtime.evaluate', { expression: 'window.OM_START()' });

for (let f = 0; f < frames; f++) {
  const expired = cdp.once('Emulation.virtualTimeBudgetExpired');
  await cdp.send('Emulation.setVirtualTimePolicy', {
    policy: 'pauseIfNetworkFetchesPending',
    budget: frameMs,
  });
  await expired;

  const shot = await cdp.send('Page.captureScreenshot', {
    format: 'jpeg', quality: 92, fromSurface: true, captureBeyondViewport: false,
  });
  await write(Buffer.from(shot.data, 'base64'));

  if (f % (FPS * 5) === 0) {
    process.stdout.write(`\r  ${f}/${frames} frames (${(f / FPS).toFixed(0)}s)   `);
  }
}

process.stdout.write(`\r  ${frames}/${frames} frames — encoding...            \n`);
ff.stdin.end();
await new Promise((res) => ff.on('close', res));
chrome.kill();
console.log('wrote', OUT);
