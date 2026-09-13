import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// Whether this build is allowed to sell anything, and what follows when it is
/// not.
///
/// The app sells its subscription through Stripe's hosted checkout. On iOS that
/// is a direct breach of App Store Review Guideline 3.1.1: digital content
/// unlocked inside the app has to be sold through In-App Purchase, and the
/// reader-app and external-link carve-outs do not cover a productivity app
/// selling its own features. Shipping it would be rejected, and repeated
/// rejections on the same guideline invite scrutiny.
///
/// StoreKit is the real answer and it is not in this version. So rather than
/// show iOS users a paywall none of them could ever complete, this build simply
/// does not sell on iOS - and gives them the paid features for nothing until it
/// can. That is a deliberate trade: a free feature is a disappointment to
/// reverse later, an unbuyable paywall is a rejected binary.
///
/// One switch, read everywhere, so "is this build allowed to sell" is answered
/// in exactly one place. Hiding the checkout call alone would not have been
/// enough - a reviewer finding any route to an external payment page is the
/// rejection, not the purchase completing.
abstract final class StorePolicy {
  /// Set in tests to exercise both platforms. A test host reports whatever OS
  /// it is running on, so without this the iOS branch - the one that matters -
  /// could never be asserted.
  @visibleForTesting
  static bool? debugCanSellOverride;

  /// False on iOS. True on Android and web, where Stripe is allowed.
  static bool get canSell {
    final override = debugCanSellOverride;
    if (override != null) return override;
    if (kIsWeb) return true;
    return !Platform.isIOS;
  }

  /// Paid features are simply on when the build cannot sell them.
  ///
  /// Entitlement still comes from the server everywhere else, so an existing
  /// subscriber who bought on web keeps exactly what they paid for; this only
  /// ever adds access, never removes it.
  static bool get unlockAllPaidFeatures => !canSell;
}
