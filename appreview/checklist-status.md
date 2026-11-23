# Checklist.pdf — status

Written for: Anj, as a working record of what the four "checks" in
Checklist.pdf actually amount to against this codebase, and what was done.

Each item is marked from evidence, not assumption. Where something is marked
done, the evidence is named so it can be re-checked. Where something is not
applicable, the reason is given rather than the item being quietly dropped.

The PDF is a transcript of four Instagram reels, not a specification, so some
items are real engineering and some are sales patter for a product. Both are
labelled as such.

---

## Check 1 — "BLA", the anti-AI-cloning shield

**Not applicable. Recommend skipping.**

The reel pitches a GitHub tool that plants decoys to exhaust an AI scraper's
budget. That protects a **public website or repository** being read file by
file. OurMynd ships to users as a compiled binary through the App Store: there
is no source tree for a scraper to walk. The marketing site is a landing page
with no proprietary logic in it.

The claims in the reel ("tested 12 kinds of files, the bot failed on every
one") are unverified and come from the tool's own marketing. If you want to
raise the cost of someone decompiling the shipped app, the real control is
build-level obfuscation, not decoys.

Nothing done. Say the word if you want the obfuscation route costed instead.

---

## Check 2 — Google Fonts and GDPR

**Real, and it was in two places, not one. Both fixed.**

Fetching a font from `fonts.googleapis.com` sends the visitor's IP address to
Google before they have agreed to anything. EU courts have repeatedly held
that to be a GDPR breach.

| Where | Before | Now |
|---|---|---|
| `website/index.html` | fetched Fredoka + Lexend from Google | self-hosted |
| `website/video.html` | same | self-hosted |
| **The app itself** | `google_fonts` fetched Inter + Atkinson at runtime | bundled, fetching off |

The app was the worse of the two and was not in the reel: `google_fonts`
downloads from `fonts.gstatic.com` the first time a family is used unless told
not to, so **every user's phone** was contacting Google on first launch,
undisclosed. That is the same category of undisclosed third-party
transmission App Review raised about the AI provider.

- `website/assets/fonts/` — 6 woff2 files, 156 KB, and `fonts.css` rewritten to
  local paths. No request to Google remains anywhere on the site.
- `assets/google_fonts/` — 8 TTFs, 2.0 MB, covering every weight the app uses
  (400, 500, 600, 700, 800, 900 for Inter; 400/700 Atkinson). Declared in
  `pubspec.yaml`.
- `GoogleFonts.config.allowRuntimeFetching = false` in `lib/main.dart`.

Both families are SIL Open Font License, so bundling is permitted. This also
satisfies the Check 4 item "license any fonts and images to use", and means
text renders on a first launch with no network.

---

## Check 3 — the security laundry list

Checked live against the running site and API rather than reasoned about.

| Item from the reel | Status |
|---|---|
| Download your whole `.git` folder | **Clean** — `/.git/config` → 404 |
| Exposed `.env` | **Clean** — `/.env` → 404 |
| Inject malware through your CDN script | **Clean** — no third-party `<script src>` on the site |
| Read your source from source maps | **Clean** — no `.map` files shipped |
| Find out which emails have accounts | **Clean** — unknown email returns a generic `invalid Google token`, no enumeration |
| Change the price at checkout | **Clean** — the client sends a plan id, the server resolves the real Stripe price (`planCatalog()`); price is never client-supplied |
| Send your password reset link to their server | **Not applicable** — no passwords; OAuth and guest only |
| Stuff leaked passwords into your login | **Not applicable** — same reason |
| Run up your SMS bill | **Not applicable** — no SMS |
| Put your site in an invisible frame | **GAP — marketing site** (see below) |
| Skip your login with one header | API enforces `requireAuth` per route; no header bypass found |
| Forge a login with your JWT secret | Depends on `JWT_SECRET` strength, which is yours to confirm in Render |
| Subdomain takeover / SSRF / path traversal | Not exhaustively tested; see note |

**The one real gap.** The API is well hardened:

```
content-security-policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'
strict-transport-security: max-age=63072000; includeSubDomains; preload
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
```

The **marketing site** only sets HSTS and nosniff. It has no
`X-Frame-Options` and no CSP, so `www.ourmynd.com` can be loaded in an
invisible iframe. Low severity for a page with no authenticated actions on it,
but it is the exact item in the reel and it is a two-line fix at the host.

Add to your host config (Vercel `vercel.json`, or Netlify `_headers`):

```json
{
  "headers": [{
    "source": "/(.*)",
    "headers": [
      { "key": "X-Frame-Options", "value": "DENY" },
      { "key": "Content-Security-Policy", "value": "frame-ancestors 'none'" },
      { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" }
    ]
  }]
}
```

I have not added this file, because the deployed site is not the `website/`
folder in this repo (the privacy and terms pages live elsewhere), so a config
committed here would not take effect and would give false comfort.

**Not covered honestly:** subdomain takeover, SSRF to cloud metadata, and path
traversal were not tested. Each needs active probing against infrastructure
rather than reading code, and probing should be deliberate and authorised
rather than a side effect. Worth a scheduled pass; say so and I will scope it.

---

## Check 4 — the compliance list

| Item | Status |
|---|---|
| Privacy policy | Present — `ourmynd.com/privacy` returns 200 |
| Terms of service | Present — returns 200 |
| Copyright page | Present — returns 200 |
| Cookie policy | **Not needed** — site sets no cookies |
| Cookie consent banner | **Not needed** — no cookies, no analytics, no trackers found anywhere on the site |
| Audit your third-party SDKs | **Done** — no analytics, ads, attribution or crash SDKs in `pubspec.yaml`. The data-touching ones are Google/Apple sign-in, LiveKit, Groq (via your server) and mail/calendar, all user-initiated |
| Don't collect unnecessary data | Consistent with the above; no passive collection found |
| Add accessibility alt text | **N/A for the site** — zero `<img>` tags; imagery is CSS/SVG |
| Add your business details | **Drafted** — registered office is in `privacy-policy-additions.md`, awaiting the legal entity name and deployment |
| License any fonts and images | **Done** — all bundled fonts are SIL OFL |
| Data deletion request option | **Present in-app** — `account_data_screen.dart` deletes the account; also required by Apple 5.1.1(v) |
| Refund policy | **Missing** — you sell subscriptions on web/Android via Stripe, so this should exist |
| Age consent if collecting kids' data | **Open question** — depends on your declared age rating |
| Unsubscribe link in emails | **Open** — the app can send mail; transactional mail is exempt, marketing mail is not |
| Remove dark patterns / hidden feeds / fake reviews / unsupported claims | No instances found; these are judgement calls on copy, not code |
| Fix your colour contrast ratio | **Open** — worth doing as part of the dark mode work |
| Add keyboard navigation | Site only; low priority for a landing page |

---

## What is left

1. **Deploy** the privacy policy additions (AI/Groq disclosure + registered
   office), and fill in the legal entity name.
2. **Add the frame-busting headers** at whatever host serves `ourmynd.com`.
3. **Write a refund policy** — you take money through Stripe today.
4. Decide on **age rating / kids' data** and **marketing email unsubscribe**.
5. Optional: a deliberate, authorised pass on subdomain takeover, SSRF and
   path traversal.
