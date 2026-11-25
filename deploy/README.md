# Which server the app talks to

`servers.json` in this folder is the **source of truth** for the address every
installed OurMynd app uses. The app re-reads it at launch and on a foreground
return, so changing it moves live installs with no new build and no App Review.

It was previously maintained only on the website: untracked, unreviewed and
unvalidated. It is kept here so a change is a diff, and so the tests can check
it before it goes anywhere.

## Current setup: one server

| | Address | State in Render |
|---|---|---|
| **Live** | `https://ourmynd-server.onrender.com` | running, paid plan — the server this file names |
| Spare | `https://ourmynd-server-3bvh.onrender.com` | the lifeboat from the suspension; suspend it once traffic has moved |

Only one address is listed, and that is deliberate. A standby is worth listing
only when it shares **both** `DATABASE_URL` and `JWT_SECRET` with the live
server. These two share the database - same Supabase project, checked by
comparing the `postgres.<ref>` segment on 2026-11-25 - but **not** the secret:
`render.yaml` sets `JWT_SECRET` with `generateValue: true`, so each service
minted its own. A token issued by one is rejected by the other, measured: the
same session returned 200 on 3bvh and 401 on ourmynd-server.

So a failover today would not lose anybody's data, but it would sign every user
out mid-session. That is why the second address stays out of the file.

The app trusts both addresses permanently, so switching is config, not a
release.

### If you want a real standby

Copy `JWT_SECRET` from one service to the other in the Render dashboard. Once
both the database and the secret match, listing two addresses is a genuine hot
spare and a failover is invisible. Until then, one address only.

### A note on what this file said before

It used to claim the two servers shared neither the database nor the secret.
Half of that was wrong, and the error was expensive: it is why the published
file sat on the lifeboat for days after the code had moved back. Check a claim
like that against the dashboard before trusting it.

## To move to the other server

1. Put the other address in **both** `primary` and `api` in `servers.json`.
   Build 20 and the status page read `api`; newer builds read `primary`.
2. Run `flutter test test/core/servers_file_test.dart`.
   **A file the app rejects is not a runtime error — it is silently ignored**,
   so you would publish a move, nothing would move, and nothing would say why.
   This test is the only thing that will tell you.
3. Update `ApiConfig.hostedApi` in `lib/core/services/api_config.dart` to the
   same address. That constant is what a phone uses before it has ever reached
   the file, and the test above fails if the two disagree. It only reaches users
   on the next build, which is fine — it is the last resort, not the main path.
4. Publish the file to `https://www.ourmynd.com/servers.json`.
5. In Render, start the server you are moving **to**, confirm `/health` returns
   `{"ok":true,"db":"up"}`, then suspend the one you are moving **from**.

Installs pick it up within about 12 minutes of a foreground return, or
immediately on a cold start.

## Before you ever list two servers again

Both must share one `DATABASE_URL` and one `JWT_SECRET`. A token minted by one
is rejected by the other, so mismatched secrets do not degrade the app on
failover — they **sign every user out mid-session** and every request returns
401.

## Why you cannot point this anywhere you like

`lib/core/services/server_directory.dart` accepts an address only if it is
`https`, carries no path or credentials, and is either one of two exactly-named
Render hosts or any subdomain of `ourmynd.com`. Everything else is ignored and
the current address stays.

That exactness is the point. Whoever can change this file decides where every
installed app sends its session token on the next request, and nothing on the
phone would look wrong. `onrender.com` is shared hosting, so a suffix rule would
have let anyone who tampered with the file stand up `harvester.onrender.com` and
collect every session. Naming the hosts exactly means the worst a hostile edit
can do is move traffic between servers we already own.

**To move to a host outside that fence**, add it to `_allowedHosts` and ship a
build. The easier route is `api.ourmynd.com`: any `ourmynd.com` subdomain is
already accepted, so pointing a CNAME at whichever server is current lets the
app follow it anywhere, permanently, without a release.

## Do not

- Edit the live file to test something. Real installs read it. Point a test
  build at your own copy with
  `--dart-define=OURMYND_SERVER_FILE=https://.../servers.json`.
- Add a keep-alive pinger to stop a server sleeping. The probe that wakes one is
  already allowed 70 seconds for exactly that reason.
