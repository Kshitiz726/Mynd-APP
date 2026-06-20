import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';

const r = Router();

r.get('/notes', requireAuth, async (req, res, next) => {
  try {
    const q = req.query.q as string | undefined;
    let query = `SELECT id as "_id", title, preview, content, tags, is_pinned as "isPinned", updated_at as "updatedAt" FROM notes WHERE user_id = $1`;
    const params: any[] = [req.user.id];

    if (q) {
      query += ` AND (title ILIKE $2 OR content ILIKE $2 OR $2 = ANY(tags))`;
      params.push(`%${q}%`);
    }
    
    query += ` ORDER BY updated_at DESC`;
    const rows = await db.any(query, params);
    res.json(rows);
  } catch (err) {
    next(err);
  }
});

r.post('/notes', requireAuth, async (req, res, next) => {
  try {
    const { title, preview, content, tags } = req.body;
    const row = await db.one(
      `INSERT INTO notes(user_id, title, preview, content, tags) 
       VALUES($1, $2, $3, $4, $5) 
       RETURNING id as "_id", title, preview, content, tags, is_pinned as "isPinned", updated_at as "updatedAt"`,
      [req.user.id, title, preview, content, tags || []]
    );
    res.status(201).json(row);
  } catch (err) {
    next(err);
  }
});

r.put('/notes/:id', requireAuth, async (req, res, next) => {
  try {
    const { isPinned, title, preview, content, tags } = req.body;
    
    if (isPinned !== undefined) {
      const row = await db.oneOrNone(
        `UPDATE notes SET is_pinned = $1, updated_at = now() 
         WHERE id = $2 AND user_id = $3 
         RETURNING id as "_id", title, preview, content, tags, is_pinned as "isPinned", updated_at as "updatedAt"`,
        [isPinned, req.params.id, req.user.id]
      );
      if (!row) return res.status(404).json({ error: 'Not found' });
      return res.json(row);
    }

    if (title !== undefined) {
      const row = await db.oneOrNone(
        `UPDATE notes SET title = $1, preview = $2, content = $3, tags = $4, updated_at = now()
         WHERE id = $5 AND user_id = $6
         RETURNING id as "_id", title, preview, content, tags, is_pinned as "isPinned", updated_at as "updatedAt"`,
        [title, preview, content, tags || [], req.params.id, req.user.id]
      );
      if (!row) return res.status(404).json({ error: 'Not found' });
      return res.json(row);
    }

    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

r.delete('/notes/:id', requireAuth, async (req, res, next) => {
  try {
    const result = await db.result(`DELETE FROM notes WHERE id = $1 AND user_id = $2`, [req.params.id, req.user.id]);
    if (result.rowCount === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ ok: true });
  } catch (err) {
    next(err);
  }
});

export default r;
