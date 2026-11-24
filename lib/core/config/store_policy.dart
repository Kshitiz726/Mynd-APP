import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// Which payment rail this build is allowed to use, and what follows when it
/// has none.
///
/// Two separate questions, and conflating them is what the earlier version of
/// this file got wrong. "May this build sell?" and "may this build open
/// Stripe's hosted checkout?" were one switch, so turning selling on for iOS
/// would also have handed iOS a route to an external payment page - App Store
/// Review Guideline 3.1.1, the very thing the switch existed to prevent. A
/// reviewer finding ANY route to an outside payment page is the rejection,
/// whether or not a purchase completes there.
///
/// So: iOS sells, through StoreKit only. Everywhere else sells through Stripe.
/// Nothing sells through both, and iOS cannot reach Stripe's pages at all.
abstract final class StorePolicy {
  /// Set in tests to exercise a build that may not sell at all. A test host
  /// reports whatever OS it is running on, so without this the no-sale branch
  /// could never be asserted.
  @visibleForTesting
  static bool? debugCanSellOverride;

  /// Set in tests to exercise the iOS rail from a macOS test host, which is
  /// the only way the StoreKit branch gets covered.
  @visibleForTesting
  static bool? debugUseStoreKitOverride;

  /// True where the subscription must be sold through Apple's StoreKit.
  ///
  /// Not "is this an Apple platform": macOS builds are distributed outside the
  /// App Store here, so they keep the Stripe rail. This is iOS specifically.
  static bool get useStoreKit {
    final override = debugUseStoreKitOverride;
    if (override != null) return override;
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  /// Whether this build may sell at all.
  ///
  /// True everywhere now that iOS has a rail of its own. Kept as a switch
  /// rather than inlined `true` because the no-sale case is a real state - a
  /// platform where StoreKit is missing and Stripe is not permitted - and
  /// because [unlockAllPaidFeatures] is defined in terms of it.
  static bool get canSell => debugCanSellOverride ?? true;

  /// Whether Stripe's hosted pages (checkout, billing portal) may be opened.
  ///
  /// False on iOS, and that is the whole point of this file. Both of those
  /// pages can take money, so both are refused at the provider rather than
  /// merely hidden in the UI.
  static bool get canUseExternalCheckout => canSell && !useStoreKit;

  /// Paid features are simply on when the build cannot sell them.
  ///
  /// This no longer fires in any shipping build: every platform has a rail.
  /// It stays because the alternative to a free feature is a paywall nobody
  /// can complete, and if a rail is ever lost again that is still the right
  /// answer. Entitlement otherwise comes from the server, so this only ever
  /// adds access and never removes it.
  static bool get unlockAllPaidFeatures => !canSell;
}
