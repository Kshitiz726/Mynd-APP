import 'package:flutter/material.dart';

import '../../core/routes/app_routes.dart';
import '../../providers/health_consent_provider.dart';
import 'health_consent_screen.dart';

/// What happens between signing in and landing in the app.
///
/// The three sign-in paths (Google, Apple, and the test account) all used to
/// end with the same `pushReplacementNamed(shell)` copied into each of them.
/// Anything that needs to happen once per account before the app opens has to
/// be added to all three or it silently does not happen for one provider, so
/// they now go through here instead.
///
/// Today that is one thing: the health-data consent question, asked on its own
/// screen straight after the account exists and before the app is usable. The
/// coach gates on the same answer independently (see CoachScreen.build), so
/// this is not the only thing standing between a fresh account and a coaching
/// conversation - it is the part that makes it an onboarding step rather than
/// an interruption the first time someone opens the coach.
abstract final class OnboardingGate {
  /// Land in the app, asking anything that has to be asked first.
  ///
  /// Replaces the current route either way, so the login screen is never
  /// behind what comes next and the back gesture cannot return to it.
  static Future<void> enter(BuildContext context) async {
    final consent = HealthConsentProvider.instance;

    // Ask the server before deciding. A returning account may have answered
    // this on another device, and re-asking someone who already said no is
    // both annoying and, since the answer is recorded, wrong.
    //
    // If that call fails we go straight in and ask later. Showing the screen
    // anyway would put an unanswerable question in front of someone who has
    // just signed in: recording the decision needs the same server that just
    // failed, so the only two outcomes would be a toast and a dead end.
    // Nothing health-related is processed in the meantime - the gate stays
    // shut on its own, without a screen having to hold it.
    await consent.refresh();
    if (!context.mounted) return;

    if (!consent.mustAsk) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.shell);
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        // `ctx` is this route's own context, deliberately - not the enclosing
        // `context`. pushReplacement destroys the route that `context` belongs
        // to, so by the time onDecided runs it is a deactivated widget and
        // Navigator.of throws on it. The consent had already been saved at
        // that point, so the failure surfaced as "couldn't save that, check
        // your connection" on a request that had succeeded.
        builder: (ctx) => HealthConsentScreen(
          // Both answers lead into the app. That is the whole point of the
          // screen being a question rather than a gate.
          onDecided: (_) =>
              Navigator.of(ctx).pushReplacementNamed(AppRoutes.shell),
        ),
      ),
    );
  }
}
