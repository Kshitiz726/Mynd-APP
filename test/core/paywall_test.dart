import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/config/store_policy.dart';
import 'package:ourmynd/core/services/billing_service.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/paywall/paywall_screen.dart';
import 'package:ourmynd/providers/premium_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';

/// The screen that takes money, and the three things on it that have to work.
///
/// All three were broken. "Restore Purchase", "Privacy Policy" and "Terms of
/// Use" were plain Text widgets with no handler - they looked like links,
/// read like links, and did nothing. Apple requires functional links to the
/// terms and the privacy policy on the screen that sells a subscription, and
/// a working restore for anybody who has already paid and reinstalled. A
/// label that only looks like a link fails both, and the failure is invisible
/// in a screenshot, which is the only way anybody had been looking at this
/// screen.
void main() {
  // The paywall reaches PremiumProvider, which reaches a platform channel the
  // first time StoreKit is touched.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    StorePolicy.debugCanSellOverride = null;
    StorePolicy.debugUseStoreKitOverride = null;
  });

  /// StoreKit's shape: a price already formatted by the store.
  final plans = [
    BillingPlan.fromStore(
      planId: 'pro_month',
      interval: 'month',
      displayPrice: '£6.99',
      rawPrice: 6.99,
      currencyCode: 'GBP',
    ),
    BillingPlan.fromStore(
      planId: 'pro_year',
      interval: 'year',
      displayPrice: '£59.99',
      rawPrice: 59.99,
      currencyCode: 'GBP',
    ),
  ];

  /// The whole offer, in one viewport.
  ///
  /// The default 800x600 test surface cuts the ListView off well above the
  /// footer, so the links under test are never laid out and every finder
  /// comes back empty for a reason that has nothing to do with the links.
  Future<void> tallScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  Future<PremiumProvider> pumpPaywall(WidgetTester tester) async {
    await tallScreen(tester);
    final premium = PremiumProvider();
    final settings = SettingsProvider();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: premium),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const PaywallScreen(),
      ),
    ));
    // initState fires loadPlans against a server that is not there; seeding
    // afterwards is what the screen would have got from a store that answered.
    premium.debugSeedPlans(plans);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return premium;
  }

  testWidgets('all three footer links are really tappable', (tester) async {
    await pumpPaywall(tester);

    for (final label in [
      'Restore Purchase',
      'Privacy Policy',
      'Terms of Use'
    ]) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: '$label is missing');

      // A tap action in the semantics tree is the thing that was absent. It
      // cannot be faked by styling, which is all the old row had.
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(finder),
        matchesSemantics(label: label, hasTapAction: true),
        reason: '$label looks like a link but does nothing',
      );
      handle.dispose();
    }
  });

  testWidgets('the store price is shown verbatim, not reformatted',
      (tester) async {
    await pumpPaywall(tester);
    // Monthly is selected by default. Apple requires its own localised string
    // to be what appears, and our formatter knows three currency symbols.
    expect(find.text('£6.99'), findsOneWidget);
  });

  testWidgets('switching to yearly reprices and shows the saving',
      (tester) async {
    await pumpPaywall(tester);

    await tester.tap(find.text('Yearly'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('£59.99'), findsOneWidget);
    // 59.99 against 12 x 6.99 = 83.88 is a 28% saving. The number matters
    // less than that it is computed rather than written on the card.
    expect(find.textContaining('Save '), findsOneWidget);
  });

  testWidgets('the renewal terms are on the screen that sells it',
      (tester) async {
    await pumpPaywall(tester);
    // Guideline 3.1.2: the length of the subscription and the fact that it
    // renews have to be here, not only behind the terms link.
    expect(find.textContaining('Renews automatically every month'),
        findsOneWidget);

    await tester.tap(find.text('Yearly'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.textContaining('Renews automatically every year'), findsOneWidget);
  });

  testWidgets('a store that says nothing says so, rather than showing a dash',
      (tester) async {
    await tallScreen(tester);
    final premium = PremiumProvider();
    final settings = SettingsProvider();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: premium),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const PaywallScreen(),
      ),
    ));
    premium.debugSeedPlans(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Plans are unavailable right now'), findsOneWidget);
    // The old screen rendered a tier card with an em dash where the price
    // went, which reads as a broken app and invites a tap on Subscribe.
    expect(find.text('Subscribe to Pro'), findsNothing);
  });
}
