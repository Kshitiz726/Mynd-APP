import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/config/store_policy.dart';
import 'package:ourmynd/core/routes/app_router.dart';
import 'package:ourmynd/core/routes/app_routes.dart';
import 'package:ourmynd/features/paywall/paywall_screen.dart';
import 'package:ourmynd/providers/premium_provider.dart';

/// iOS sells, but only through StoreKit.
///
/// What gets an app rejected under Guideline 3.1.1 is a reviewer finding ANY
/// route to an external payment page, so hiding the buttons is not the test -
/// being unable to reach the page is. That invariant used to be free, because
/// iOS could not sell at all; now that it can, the two questions ("may this
/// build sell?" and "may it open Stripe?") are separate switches and the
/// second one has to be held down by a test.
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
  // IapService reaches a platform channel the first time it is touched.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    StorePolicy.debugCanSellOverride = null;
    StorePolicy.debugUseStoreKitOverride = null;
  });

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

  group('on the StoreKit rail', () {
    setUp(() => StorePolicy.debugUseStoreKitOverride = true);

    test('the paywall is reachable', () {
      // The point of the split. Before it, making Stripe unreachable on iOS
      // also made the paywall unreachable, which is why iOS shipped with the
      // paid features simply given away.
      expect(StorePolicy.canSell, isTrue);
      final page = AppRouter.builderFor(AppRoutes.paywall)(_DummyContext());
      expect(page, isA<PaywallScreen>());
    });

    test('Stripe checkout and the billing portal are still unreachable',
        () async {
      expect(StorePolicy.canUseExternalCheckout, isFalse);
      final p = PremiumProvider();
      // Not "the button is hidden": these are the calls that open a page which
      // can take money, and they have to refuse on their own.
      expect(await p.startCheckout('pro_month'), isFalse);
      expect(await p.openBillingPortal(), isFalse);
    });

    test('paid features are not given away once they can be sold', () {
      expect(StorePolicy.unlockAllPaidFeatures, isFalse);
      expect(PremiumProvider().isPremium, isFalse);
    });

    test('subscriptions are managed at Apple, not at a page of ours', () {
      // Apple owns the subscription, so this is the only URL that can cancel
      // or change it. A typo here is a dead end on the one screen a subscriber
      // goes looking for.
      expect(PremiumProvider.appleSubscriptionsUrl,
          'https://apps.apple.com/account/subscriptions');
    });
  });

  group('on the Stripe rail', () {
    setUp(() => StorePolicy.debugUseStoreKitOverride = false);

    test('checkout is permitted', () {
      expect(StorePolicy.canUseExternalCheckout, isTrue);
    });
  });
}
