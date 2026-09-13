import { Router } from 'express';
import { db } from '../db.js';
import { requireAuth } from '../auth.js';
import { toggleReaction } from '../services/reactions.js';
import { pushNotification } from '../services/notify.js';
import { notBlockedSql } from '../services/moderation.js';

const r = Router();

// ── Create a post (body + mood + tags) ──
r.post('/posts', requireAuth, async (req, res) => {
  const { body, mood, tags } = req.body as {
    body: string;
    mood?: 'high' | 'low' | 'dead';
    tags?: string[];
  };
  if (!body?.trim()) return res.status(400).json({ error: 'empty post' });

  const post = await db.tx(async (t) => {
    const p = await t.one(
      `insert into posts(author_id, body, mood) values($1,$2,$3) returning *`,
      [req.user.id, body.trim(), mood ?? null],
    );
    const clean = [...new Set((tags ?? []).map((x) => x.replace(/^#/, '').toLowerCase().trim()))]
      .filter(Boolean)
      .slice(0, 5);
    if (clean.length) {
      await t.none(`insert into post_tags(post_id, tag) select $1, unnest($2::text[])`, [
        p.id,
        clean,
      ]);
    }
    // Include the author fields + empty reactions so the client can render the
    // new card immediately in the same shape the feed query returns.
    return {
      ...p,
      tags: clean,
      display_name: req.user.displayName,
      initial: req.user.initial,
      avatar_color: req.user.avatarColor,
      my_reactions: [],
    };
  });
  res.status(201).json(post);
});

// ── Feed (keyset pagination; optional #tag filter) ──
r.get('/feed', requireAuth, async (req, res) => {
  const { cursor, tag } = req.query as { cursor?: string; tag?: string };
  const rows = await db.any(
    `
    select p.*, u.display_name, u.initial, u.avatar_color, u.avatar_text_color,
           coalesce(array_agg(distinct pt.tag) filter (where pt.tag is not null), '{}') as tags,
           array(select kind::text from reactions x where x.post_id=p.id and x.user_id=$1) as my_reactions
    from posts p
    join users u on u.id = p.author_id
    left join post_tags pt on pt.post_id = p.id
    -- Blocking applies here first, because the feed is where a reviewer will
    -- check it. Always a WHERE rather than one of the conditional ones, so the
    -- filter cannot depend on whether a tag or a cursor happened to be passed.
    where ${notBlockedSql('p.author_id', '$1')}
    ${tag ? `and exists (select 1 from post_tags f where f.post_id=p.id and f.tag=$3)` : ''}
    ${cursor ? `and p.created_at < $2` : ''}
    group by p.id, u.id
    order by p.created_at desc
    limit 20`,
    tag ? [req.user.id, cursor ?? null, tag] : [req.user.id, cursor ?? null],
  );
  res.json({ posts: rows, nextCursor: rows.at(-1)?.created_at ?? null });
});

// ── Comments: post + fetch a whole thread in path order ──
r.post('/posts/:id/comments', requireAuth, async (req, res) => {
  const { body, parentId } = req.body as { body: string; parentId?: string };
  const comment = await db.tx(async (t) => {
    const id = (await t.one(`select gen_random_uuid() as id`)).id;
    const path = parentId
      ? `${(await t.one(`select path from comments where id=$1`, [parentId])).path}.${id.replace(/-/g, '')}`
      : id.replace(/-/g, '');
    return t.one(
      `insert into comments(id, post_id, author_id, parent_id, body, path)
       values($1,$2,$3,$4,$5,$6) returning *`,
      [id, req.params.id, req.user.id, parentId ?? null, body, path],
    );
  });

  // Notify the post's author that someone commented (skip self-comments). This
  // is what feeds the "post comments" section of the Alerts dashboard.
  const post = await db.oneOrNone<{ author_id: string }>(
    `select author_id from posts where id=$1`,
    [req.params.id],
  );
  if (post && post.author_id !== req.user.id) {
    await pushNotification(post.author_id, 'post_comment', {
      name: req.user.displayName,
      userId: req.user.id,
      postId: req.params.id,
      commentId: comment.id,
      preview: (body ?? '').slice(0, 120),
    });
  }

  res.status(201).json(comment);
});

r.get('/posts/:id/comments', requireAuth, async (req, res) => {
  const rows = await db.any(
    `select c.*, u.display_name, u.initial, u.avatar_color,
            (select count(*) from comment_upvotes cu where cu.comment_id = c.id) as upvote_count,
            exists(select 1 from comment_upvotes cu where cu.comment_id = c.id and cu.user_id = $2) as has_upvoted
     from comments c join users u on u.id = c.author_id
     where c.post_id=$1 and ${notBlockedSql('c.author_id', '$2')}
     order by c.path`,
    [req.params.id, req.user.id],
  );
  res.json({ comments: rows });
});

// ── Comment Upvote toggle ──
r.post('/comments/:id/upvote', requireAuth, async (req, res) => {
  const { active } = req.body as { active: boolean };
  if (active) {
    await db.none(`insert into comment_upvotes(comment_id, user_id) values($1, $2) on conflict do nothing`, [
      req.params.id,
      req.user.id,
    ]);
  } else {
    await db.none(`delete from comment_upvotes where comment_id=$1 and user_id=$2`, [
      req.params.id,
      req.user.id,
    ]);
  }
  res.json({ ok: true });
});

// ── Reaction toggle (REST fallback; socket path is primary) ──
r.post('/posts/:id/reactions', requireAuth, async (req, res) => {
  const out = await toggleReaction(req.params.id, req.user.id, req.body.kind);
  res.json(out);
});

export default r;
