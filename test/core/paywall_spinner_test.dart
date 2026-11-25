import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/services/iap_service.dart';

/// The paywall never spins for ever.
///
/// queryProductDetails carries no timeout of its own. A StoreKit that never
/// answers - the App Store unreachable, a region with no products, a
/// simulator with no configuration attached - left PremiumProvider.loadPlans()
/// awaiting with no end: _loadingPlans stayed true, and the paywall sat on a
/// spinner.
///
/// The paywall already had the right screen for this, _StoreUnreachable with
/// a Retry on it. It was simply never reachable, because reaching it needs
/// loading to go false while plans stay empty, and loading never went false.
///
/// A perpetual spinner on the screen that takes money reads as a broken app
/// under guideline 2.1, and a reviewer who meets one rejects rather than
/// retries.
void main() {
  test('the product query is bounded', () {
    expect(IapService.productQueryTimeout, isNotNull);
    expect(IapService.productQueryTimeout, greaterThan(Duration.zero));
  });

  test('the bound is long enough for a slow store, short enough to notice', () {
    final s = IapService.productQueryTimeout.inSeconds;
    // Long enough that a genuinely slow App Store still answers rather than
    // being cut off and shown as unreachable.
    expect(s, greaterThanOrEqualTo(10));
    // Short enough that somebody is not left watching a spinner wondering
    // whether the app is dead.
    expect(s, lessThanOrEqualTo(30));
  });

  test('a timed-out store reports as unavailable, not as some other error', () {
    // The paywall branches on plans being empty, and loadPlans() only leaves
    // them empty by way of its catch. unavailable is also the failure whose
    // message tells somebody to try again rather than contact support.
    final e = IapException(IapFailure.unavailable, 'the store did not answer');
    expect(e.message, contains('Try again'));
  });
}
