import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/config/store_policy.dart';
import 'package:ourmynd/core/routes/app_router.dart';
import 'package:ourmynd/core/routes/app_routes.dart';
import 'package:ourmynd/features/paywall/paywall_screen.dart';
import 'package:ourmynd/providers/premium_provider.dart';

/// iOS may not sell anything in this build.
///
/// The app sells its subscription through Stripe's hosted checkout, which on
/// iOS breaches App Store Review Guideline 3.1.1. What gets an app rejected is
/// a reviewer finding ANY route to an external payment page, so hiding the
/// buttons is not the test - being unable to reach the page is.
/// A BuildContext is required by the signature and never touched: none of
/// these pages look anything up during construction.
class _Nothing extends StatelessWidget {
  const _Nothing();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DummyContext extends StatelessElement {
  _DummyContext() : super(const _Nothing());
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorePolicy.debugCanSellOverride = null);

  group('where the build may not sell', () {
    setUp(() => StorePolicy.debugCanSellOverride = false);

    test('the paywall route resolves to something that is not the paywall', () {
      // The page, not the Route. The Route object is byte-identical in both
      // modes, so asserting on it passes for the wrong reason; constructing
      // the page is enough to tell them apart and does not mount anything.
      final page = AppRouter.builderFor(AppRoutes.paywall)(_DummyContext());
      expect(page, isNot(isA<PaywallScreen>()),
          reason: 'the paywall must be unreachable, not merely unlinked');
    });

    test('checkout and the billing portal refuse to open', () async {
      final p = PremiumProvider();
      expect(await p.startCheckout('pro_month'), isFalse);
      expect(await p.openBillingPortal(), isFalse);
    });

    test('paid features are unlocked instead of dangled', () {
      expect(StorePolicy.unlockAllPaidFeatures, isTrue);
      expect(PremiumProvider().isPremium, isTrue,
          reason: 'an unbuyable paywall is worse than a free feature');
    });
  });

  group('where the build may sell', () {
    setUp(() => StorePolicy.debugCanSellOverride = true);

    test('the paywall route resolves to the paywall', () {
      // The other half of the pair. Without it the test above would pass just
      // as happily against a router that never builds the paywall at all.
      final page = AppRouter.builderFor(AppRoutes.paywall)(_DummyContext());
      expect(page, isA<PaywallScreen>());
    });

    test('entitlement comes from the server, not from the policy', () {
      expect(StorePolicy.unlockAllPaidFeatures, isFalse);
      // A fresh provider has not heard from the server yet, so it is free.
      expect(PremiumProvider().isPremium, isFalse);
    });
  });
}
