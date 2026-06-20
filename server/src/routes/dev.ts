import { Router } from 'express';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { db } from '../db.js';

// DEV ONLY. Mints a JWT for a seeded user so the Flutter app can authenticate
// without a full login flow. Mounted only when NODE_ENV !== production.
const r = Router();

const SEEDED: Record<string, string> = {
  sam: '11111111-1111-1111-1111-111111111111',
  maya: '22222222-2222-2222-2222-222222222222',
  leo: '33333333-3333-3333-3333-333333333333',
};

r.get('/dev/token', async (req, res) => {
  const who = String(req.query.user ?? 'sam').toLowerCase();
  const id = SEEDED[who] ?? SEEDED.sam;

  const u = config.hasDb
    ? await db.oneOrNone(`select id, display_name, avatar_color from users where id=$1`, [id])
    : null;
  const name = u?.display_name ?? 'Sam';

  const token = jwt.sign(
    { sub: id, name, color: u?.avatar_color ?? '#6366F1' },
    config.jwtSecret,
    { expiresIn: '30d', issuer: config.jwtIssuer },
  );
  res.json({ token, userId: id, displayName: name });
});

export default r;
