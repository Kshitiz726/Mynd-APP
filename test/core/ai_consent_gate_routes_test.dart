import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every route that sends a user's content to the AI provider must refuse to
/// do it without their agreement on file.
///
/// This reads the server source rather than calling the server, which is an
/// odd-looking test and is deliberate: there is no test runner on the Node
/// side, and the failure this guards against is not a logic bug but an
/// omission. The gate was written once, inline, inside `/coach/completions`.
/// Four other routes sent the same user content to the same provider and none
/// of them had it - including `/coach/transcribe`, which sends recorded audio.
/// Somebody who declined could still have their words and their voice sent to
/// Groq by any of the four.
///
/// Guideline 5.1.2(i) is the reason it matters, but the reason it is pinned
/// here is that adding a sixth route and forgetting the gate is the easiest
/// mistake in this file to make, and the one nothing else would catch.
void main() {
  final coach = File('server/src/routes/coach.ts');

  test('the server source is where this test thinks it is', () {
    // Otherwise a moved file turns this into a test that passes by finding
    // nothing, which is the worst kind.
    expect(coach.existsSync(), isTrue,
        reason: 'server/src/routes/coach.ts has moved; update this test');
  });

  test('every coach route that sends user content requires AI consent', () {
    final src = coach.readAsStringSync();

    // Read-only routes send nothing to the provider, so they stay open:
    // declining turns the coach off, not the account.
    const sendsNothingOut = {'/coach/quota'};

    final routes = RegExp(r"r\.(post|get)\('(/coach/[\w-]+)',([^\n]*)")
        .allMatches(src)
        .map((m) => (
              verb: m.group(1)!,
              path: m.group(2)!,
              middleware: m.group(3)!,
            ))
        .toList();

    expect(routes, isNotEmpty,
        reason: 'no coach routes matched; the route style has changed');

    final ungated = [
      for (final r in routes)
        if (!sendsNothingOut.contains(r.path) &&
            !r.middleware.contains('requireAiConsent'))
          '${r.verb.toUpperCase()} ${r.path}',
    ];

    expect(ungated, isEmpty,
        reason: 'these routes send user content to the AI provider without '
            'checking consent: ${ungated.join(', ')}');
  });

  test('the gate fails closed when there is no user', () {
    final consent = File('server/src/routes/consent.ts').readAsStringSync();
    expect(consent, contains('export async function requireAiConsent'),
        reason: 'the middleware has been renamed or removed');
    // The lookup can fail without the user having declined, and the two must
    // not be reported alike. Express 4 does not catch a rejection thrown out
    // of async middleware, so an unguarded failure here takes the process
    // down rather than answering - which is exactly what a server whose
    // migration has not been run would do on its first coach request.
    expect(consent, contains('ai_consent_unavailable'),
        reason: 'a failed lookup must answer, not throw');

    // One implementation. Four routes of five were missing the gate because
    // it was a line written inside a single handler rather than something
    // every route had to opt out of.
    final reimplemented = [
      for (final f in Directory('server/src/routes').listSync().whereType<File>())
        if (f.path.endsWith('.ts') &&
            !f.path.endsWith('consent.ts') &&
            f.readAsStringSync().contains("code: 'ai_consent_required'"))
          f.path,
    ];
    expect(reimplemented, isEmpty,
        reason: 'these files re-implement the refusal instead of using the '
            'middleware: ${reimplemented.join(', ')}');
  });
}
