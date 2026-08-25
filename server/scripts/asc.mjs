// App Store Connect API helper. Lives under server/ because ESM resolves
// imports from the file's own directory tree and ignores NODE_PATH - running
// this from /tmp cannot find jsonwebtoken.
import jwt from 'jsonwebtoken';
import { readFileSync } from 'node:fs';

const kid = process.env.ASC_KEY_ID || '945G9CXKWC';
const keyPath = process.env.HOME + '/.appstoreconnect/private_keys/AuthKey_' + kid + '.p8';
const key = readFileSync(keyPath);

export function token() {
  if (!process.env.ASC_ISSUER_ID) throw new Error('ASC_ISSUER_ID not set');
  return jwt.sign({ iss: process.env.ASC_ISSUER_ID, aud: 'appstoreconnect-v1' }, key,
    { algorithm: 'ES256', expiresIn: '15m', header: { alg: 'ES256', kid, typ: 'JWT' } });
}

export async function api(path, opts = {}) {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, {
    ...opts,
    headers: { Authorization: 'Bearer ' + token(), 'Content-Type': 'application/json', ...(opts.headers || {}) },
  });
  const txt = await r.text();
  let body; try { body = JSON.parse(txt); } catch { body = txt; }
  return { status: r.status, ok: r.ok, body };
}
