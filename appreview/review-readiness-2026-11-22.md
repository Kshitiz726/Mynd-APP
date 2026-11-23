# OurMynd review readiness — 22 Nov 2026

Written for: Anj, to review by hand before starting the 3.1.1 payments work.

Scope: everything touched today, every App Review check I could verify against
evidence, and the list of things that still block a submission. Each row says
how it was established, so you can re-check any of it.

---

## 1. Fixed today

| # | Was | Now | Where |
|---|---|---|---|
| 1 | Consent **could not be given at all**. `grant()` was the POST and nothing else, so with `/api/consent/ai` returning 404 the screen threw "check your connection" and saved nothing. | Recorded on the device first, synced to the server after, retried on next launch. Cannot throw. | `lib/providers/ai_consent_provider.dart` |
| 2 | Consent was asked later, in the coach, after the user had already connected a provider. | Asked at the moment of connecting, before anything can be sent. | `lib/features/profile/widgets/ai_connect_sheet.dart` |
| 3 | "Connect Puter" opened a blank screen that never finished. | Restored `PuterConnectScreen` (deleted in an earlier change) and gave it a real UI. | `lib/features/coach/puter_connect_screen.dart` |
| 4 | "Need help? Talk to Mynd" in Focus led to a screen with **no nav bar, no back button, and an inert drawer button**. A dead end. | Header draws a back control when the screen was pushed. | `lib/features/coach/coach_screen.dart`, `lib/core/routes/app_router.dart` |
| 5 | Six icons rendered as a plain circle, including the App version and Open source licence rows. | All six mapped. `byName` now asserts in debug, and a test scans the source for every icon name the app asks for. | `lib/core/utils/om_icons.dart` |
| 6 | Dark mode: white button text at **2.40:1**, below the 3:1 floor even for bold text, and worse than the same text in light mode. | 4.78:1, and the gradient span halved so buttons read as solid with a hint of depth rather than a sweep. | `lib/core/theme/app_colors.dart` |
| 7 | Schedule tab painted a hardcoded near-white panel over the dark surface: **13.51:1**. | Uses `primaryTint`, the palette's own lilac at each end. | `lib/features/schedule/schedule_screen.dart` |
| 8 | Three coloured glows were tuned *heavier* in dark than light, so they bloomed against near-black. | Reduced below their light values. | `login_screen.dart`, `about_screen.dart`, `focus_screen.dart` |
| 9 | Brand gradient banded, worst in dark, because sRGB steps are perceptually larger at the dark end. | Ramps through Oklab. | `lib/core/theme/app_colors.dart` |
| 10 | No privacy manifest. Missing required-reason API declarations are rejected at upload with ITMS-91053, before a human sees the build. | Created, registered in the Xcode project, and **verified present at `Runner.app/PrivacyInfo.xcprivacy`** in a real build. | `ios/Runner/PrivacyInfo.xcprivacy` |

Tests: **412 passing, 0 analyzer errors or warnings.** New tests cover the
gradient maths, the icon names, the consent record, the disclosure version, and
the coach exit.

---

## 2. Verified clean, with the evidence

| Check | Evidence |
|---|---|
| Dev auth endpoints not live | `POST /api/auth/google-mock` and `GET /api/dev/token` both return **404 `{"error":"not found"}`** on both servers. That is the explicit `isProd` guard firing, not an Express fallback. |
| No tracking | No analytics, ads, attribution or crash SDK in `pubspec.yaml`. Manifest declares `NSPrivacyTracking: false` and an empty domain list. |
| 4.8 Sign in with Apple | `SignInWithApple.getAppleIDCredential` in `login_screen.dart`, alongside Google. |
| 5.1.1(v) Account deletion | `account_data_screen.dart`, "delete my account", reachable from Profile. |
| 1.4.1 No medical claims | Grepped user-facing copy for therapist/therapy/diagnose/treat/clinical/prescribe/licensed. No hits. The therapist framing exists only inside the coach prompt, which also states it is not a licensed clinician. |
| Dark text contrast | Every foreground over every surface is **5.52:1 or better**. The dark palette was never the contrast problem. |
| Permission purpose strings | 8 present: calendar (x2), camera, location (x2), microphone, photo library, speech recognition. |
| Both servers healthy | `/health` returns `{"ok":true,"db":"up"}` on each. |
| Location is not "collected" | `LocationAccuracy.low`, coordinates go only to Apple's geocoder, and the resolved town is used solely to render "for your day in \<town\>". It never enters a request body, so it is deliberately **not** declared in the manifest. |

---

## 3. Still blocking a submission, ranked

**1. Guideline 3.1.1 — Apple's finding does not match the binary. CORRECTED.**
An earlier version of this report said `paywall_screen.dart` ships a Stripe
checkout to iOS users. That was wrong, and the correction matters because it
changes what to do next.

Checked at the submitted commit, not at HEAD:
`git show ba4984c:lib/core/config/store_policy.dart` returns
`canSell => !Platform.isIOS`, and `git diff ba4984c HEAD` on that file is empty.
The 3.1.1 fix landed **before** build 19. On iOS the paywall route is not
registered, `startCheckout` and the billing portal return early, no upgrade
button is rendered, the plan card is not tappable, and the quota copy names no
plan or price. The website has no `/pricing`, `/plans`, `/upgrade` or
`/subscribe` page, so there is no purchase path reachable from the in-app
browser either.

Draft reply in `appreview/appreview-reply-311.txt`, which asks the reviewer
which screen they reached it from rather than disputing the finding outright.

**2. iOS currently gives the paid features away free.**
This is the real payment problem, and it is a business one rather than a
compliance one. `StorePolicy.unlockAllPaidFeatures` is true on iOS, so every
iOS user has Plus and Pro at no charge. That was the right call when the choice
was between an unbuyable paywall and a rejection, but In-App Purchase is what
ends it. Requirements are listed at the end of this section.

**3. `JWT_SECRET` differs between the two servers.** Your own `servers.json`
says they must match. They do not: every authenticated call in the running app
returned 401. A failover **signs every user out mid-use**, and a reviewer who
hits it sees a comprehensively broken app, which is how a 2.1 rejection starts.
Fix is in the Render dashboard, not in code. Tell me which service holds the
value you want to keep and I will name the exact field to change on the other.

**4. `/api/consent/ai` is not deployed.** 404 on both servers. The app now
records consent locally and syncs later, so nothing is broken for the user, but
the server-side gate does not exist until you deploy.

**5. Both servers are awake.** `servers.json` says to suspend the standby,
because the status checks wake it and it burns compute hours.

**6. Privacy policy additions not deployed**, and the legal entity name is still
blank in `appreview/privacy-policy-additions.md`. Apple's letter is explicit
that the in-app disclosure is necessary but **not sufficient** — the policy must
also name the data, the collection, the uses, and the third party.

**7. No refund policy.** You take money through Stripe today.

**8. `www.ourmynd.com` has no `X-Frame-Options` and no CSP**, so it is
clickjackable. Config is written out in `checklist-status.md`; not committed,
because the deployed site is not this repo's `website/` folder.

**9. App Store Connect privacy answers must match the new manifest.** The
manifest declares email, name, user ID, photos, user content, audio and health,
all linked, none for tracking. If your ASC answers say something different, the
mismatch is itself a flag.

---

## 4. What I could not verify

I have **not been able to see or tap the app.** `screencapture` is blocked
without Screen Recording permission and `simctl` has no tap command, so every
visual claim in section 1 comes from code, logs and contrast arithmetic, not
from looking. Specifically unverified by eye:

- whether dark mode now *looks* right to you, as opposed to measuring right
- the Puter sign-in actually completing, which depends on Puter's popup
  behaviour on iOS 26.5 and only a real tap proves
- iPad layout. Apple reviewed on an iPad Air 11-inch M3 and rejected on 2.1
  once already; I have not run the iPad simulator this session.

I also cannot tell you the app is "100% safe" from rejection. What I can say is
which guidelines I checked, how, and what each check found, which is the whole
of sections 2 and 3.
