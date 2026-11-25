/**
 * Replace the App Store screenshots for a version's locale.
 *
 * App Store Connect does not take a file in one request. Each screenshot is
 * reserved first (which hands back one or more upload operations, because a
 * large asset is chunked), then the bytes are PUT at those operations exactly
 * as described, then the asset is committed with an MD5 of the whole file.
 * Miss the commit and the screenshot sits in the set for ever in a state the
 * UI shows as a broken tile.
 *
 * The existing screenshots are downloaded to a backup directory before
 * anything is deleted, because a listing's screenshots are not recoverable
 * from Apple once they are gone.
 *
 *   ASC_KEY_ID=... ASC_ISSUER_ID=... node --import tsx scripts/upload_screenshots.mjs \
 *     --version <appStoreVersionId> --locale en-GB --dir ../appstore/screenshots \
 *     --type APP_IPHONE_67 --backup /tmp/old-shots [--dry-run]
 *
 * APP_IPHONE_67 is the display type that takes 1320x2868, the 6.9" slot.
 */
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import { api, token } from './asc.mjs';

const arg = (name, fallback = null) => {
  const i = process.argv.indexOf('--' + name);
  return i === -1 ? fallback : process.argv[i + 1];
};
const DRY = process.argv.includes('--dry-run');
const VERSION = arg('version');
const LOCALE = arg('locale', 'en-GB');
const DIR = arg('dir');
const TYPE = arg('type', 'APP_IPHONE_67');
const BACKUP = arg('backup');

if (!VERSION || !DIR) {
  console.error('need --version <appStoreVersionId> and --dir <folder of pngs>');
  process.exit(2);
}

const die = (msg, extra) => {
  console.error('error:', msg, extra ? JSON.stringify(extra).slice(0, 400) : '');
  process.exit(1);
};

// ---- locate the set ----------------------------------------------------
const locs = await api(`/v1/appStoreVersions/${VERSION}/appStoreVersionLocalizations?limit=20`);
const loc = (locs.body.data ?? []).find((l) => l.attributes.locale === LOCALE);
if (!loc) die(`no ${LOCALE} localization on that version`, locs.body);

const sets = await api(`/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?limit=30`);
let set = (sets.body.data ?? []).find((s) => s.attributes.screenshotDisplayType === TYPE);

if (!set) {
  if (DRY) die(`no ${TYPE} set and --dry-run, so not creating one`);
  const made = await api('/v1/appScreenshotSets', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'appScreenshotSets',
        attributes: { screenshotDisplayType: TYPE },
        relationships: {
          appStoreVersionLocalization: {
            data: { type: 'appStoreVersionLocalizations', id: loc.id },
          },
        },
      },
    }),
  });
  if (!made.ok) die('could not create the screenshot set', made.body);
  set = made.body.data;
  console.log(`created ${TYPE} set ${set.id}`);
}
console.log(`${LOCALE} / ${TYPE} -> set ${set.id}`);

// ---- back up, then clear -----------------------------------------------
const existing = await api(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=30`);
const old = existing.body.data ?? [];
console.log(`${old.length} screenshot(s) already in the set`);

if (old.length && BACKUP) {
  mkdirSync(BACKUP, { recursive: true });
  for (const s of old) {
    const tpl = s.attributes?.imageAsset?.templateUrl;
    const name = s.attributes?.fileName ?? `${s.id}.png`;
    if (!tpl) {
      console.log(`  ! ${name}: no download url, cannot back up`);
      continue;
    }
    const url = tpl.replace('{w}', s.attributes.imageAsset.width)
      .replace('{h}', s.attributes.imageAsset.height)
      .replace('{f}', 'png');
    const r = await fetch(url);
    if (!r.ok) { console.log(`  ! ${name}: download ${r.status}`); continue; }
    writeFileSync(join(BACKUP, name), Buffer.from(await r.arrayBuffer()));
    console.log(`  backed up ${name}`);
  }
}

if (DRY) {
  console.log('dry run: stopping before any delete or upload');
  process.exit(0);
}

for (const s of old) {
  const d = await api(`/v1/appScreenshots/${s.id}`, { method: 'DELETE' });
  console.log(`  deleted ${s.attributes?.fileName ?? s.id}: ${d.status}`);
}

// ---- upload -------------------------------------------------------------
const files = readdirSync(DIR).filter((f) => f.toLowerCase().endsWith('.png')).sort();
if (!files.length) die(`no .png files in ${DIR}`);
console.log(`uploading ${files.length}: ${files.join(', ')}`);

for (const file of files) {
  const path = join(DIR, file);
  const bytes = readFileSync(path);
  const name = basename(file);

  const reserved = await api('/v1/appScreenshots', {
    method: 'POST',
    body: JSON.stringify({
      data: {
        type: 'appScreenshots',
        attributes: { fileName: name, fileSize: bytes.length },
        relationships: {
          appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } },
        },
      },
    }),
  });
  if (!reserved.ok) die(`reserve failed for ${name}`, reserved.body);

  const shot = reserved.body.data;
  const ops = shot.attributes.uploadOperations ?? [];
  if (!ops.length) die(`no upload operations for ${name}`, reserved.body);

  // Raw fetch, not the api() helper: these are binary PUTs to Apple's asset
  // host with their own headers, and the helper's JSON content type would
  // corrupt them.
  for (const op of ops) {
    const headers = {};
    for (const h of op.requestHeaders ?? []) headers[h.name] = h.value;
    const chunk = bytes.subarray(op.offset, op.offset + op.length);
    const put = await fetch(op.url, { method: op.method, headers, body: chunk });
    if (!put.ok) die(`chunk upload failed for ${name}: ${put.status}`, await put.text());
  }

  const checksum = createHash('md5').update(bytes).digest('hex');
  const done = await api(`/v1/appScreenshots/${shot.id}`, {
    method: 'PATCH',
    body: JSON.stringify({
      data: {
        type: 'appScreenshots',
        id: shot.id,
        attributes: { uploaded: true, sourceFileChecksum: checksum },
      },
    }),
  });
  if (!done.ok) die(`commit failed for ${name}`, done.body);
  console.log(`  uploaded ${name} (${(bytes.length / 1024).toFixed(0)} KB)`);
}

// ---- confirm Apple actually accepted each one ---------------------------
// A committed screenshot is not a delivered one. Apple processes the asset
// afterwards and can still reject it for size or format, so the only honest
// report is the state it ends up in.
await new Promise((r) => setTimeout(r, 4000));
const after = await api(`/v1/appScreenshotSets/${set.id}/appScreenshots?limit=30`);
for (const s of (after.body.data ?? [])) {
  const st = s.attributes?.assetDeliveryState ?? {};
  const errs = (st.errors ?? []).map((e) => e.description ?? e.code).join('; ');
  console.log(`  ${s.attributes.fileName}: ${st.state}${errs ? ' - ' + errs : ''}`);
}
console.log('done');
void token;
