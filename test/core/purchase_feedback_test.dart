import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/services/iap_service.dart';

/// A tap on Subscribe always produces an answer.
///
/// The paywall is the one screen where silence is worst: somebody has just
/// been through Apple's payment sheet and cannot tell whether they have been
/// charged. Two paths used to end in nothing at all.
///
///   PremiumProvider.buy returned a bare `false` when a purchase was already
///   in flight. The paywall only reported a false on the Stripe rail, so on
///   StoreKit that false arrived as no toast, no error and no change - a dead
///   button that stayed dead until the app was force quit. _busy is set for as
///   long as a purchase is running, and a sandbox sign-in that stalls holds it
///   for a minute, which is precisely when somebody taps again.
///
///   And a StoreKit purchase that simply finished without entitlement - ask to
///   buy, a parental approval, a sandbox account that signed in but could not
///   complete - fell past both branches into the same silence.
///
/// This pins the half that is unit testable: the failure exists, and it says
/// something a person can act on.
void main() {
  test('being already in flight is a reportable failure, not a silent false',
      () {
    // The enum case has to exist for the provider to throw it rather than
    // return false.
    expect(IapFailure.values, contains(IapFailure.alreadyRunning));
  });

  test('every failure has a message, and none of them is empty', () {
    for (final f in IapFailure.values) {
      final message = IapException(f).message;
      expect(message, isNotEmpty, reason: '${f.name} has no message');
      // A message that does not end in a stop is a fragment, and these are
      // shown to people as whole sentences.
      expect(message.trim(), endsWith('.'), reason: '${f.name}: $message');
    }
  });

  test('the already-running message points at the way out', () {
    final m = IapException(IapFailure.alreadyRunning).message;
    // Restore is what actually recovers a purchase that went through while
    // the app was not listening, so the message has to name it.
    expect(m, contains('Restore Purchases'));
  });

  test('a cancelled purchase is not phrased as a failure', () {
    // Backing out of Apple's sheet is the most common thing that happens on a
    // paywall, and the paywall deliberately shows nothing for it.
    expect(IapException(IapFailure.cancelled).message, 'Purchase cancelled.');
  });
}
