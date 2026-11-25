import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/store_policy.dart';
import '../core/services/billing_service.dart';
import '../core/services/iap_service.dart';

/// Owns the user's subscription entitlement and both checkout flows.
///
/// The whole app reads [isPremium] from here to gate premium-only features.
/// There are two rails and [StorePolicy] picks which one is live:
///
///   iOS   - StoreKit. [buy] runs Apple's payment sheet, the transaction goes
///           to our server to be verified, and entitlement is re-read.
///   other - Stripe's hosted Checkout in the system browser, reconciled when
///           the app returns to the foreground.
///
/// [plans] is the same shape on both, so the paywall does not branch: on iOS
/// it is built from what StoreKit says these cost in the viewer's own
/// storefront, elsewhere from the server's Stripe catalogue.
class PremiumProvider extends ChangeNotifier {
  final _billing = BillingService.instance;

  /// Deliberately a getter, not a field.
  ///
  /// Reaching IapService.instance constructs InAppPurchase.instance, and that
  /// is not inert: on Android it registers the platform and opens a Google
  /// Play billing connection on the spot. As a field it ran for every
  /// PremiumProvider ever built - on Android, which sells through Stripe and
  /// has no use for it, and in tests, where it throws because there is no
  /// binding. Now nothing touches StoreKit until a StoreKit rail asks for it.
  IapService get _iap => IapService.instance;

  BillingStatus _status = BillingStatus.free;
  List<BillingPlan> _plans = const [];
  bool _loadingPlans = false;
  bool _busy = false; // a checkout is mid-flight

  /// The Checkout session we're waiting to reconcile when the app resumes.
  String? _pendingSessionId;

  /// Set when StoreKit itself is unreachable, which on a simulator means no
  /// StoreKit configuration file is selected in the run scheme. Worth saying
  /// on screen rather than showing an empty price, because an empty paywall
  /// looks like a bug in the app and is almost always a bug in the setup.
  bool _storeUnavailable = false;
  bool get storeUnavailable => _storeUnavailable;

  BillingStatus get status => _status;

  /// True for a real subscriber, and true for everyone on a build that is not
  /// allowed to sell. See [StorePolicy]: iOS ships without StoreKit, so the
  /// paid features are unlocked there rather than dangled behind a paywall
  /// nobody on that platform could complete.
  ///
  /// Deliberately an OR and not a replacement: a web subscriber signing in on
  /// iOS keeps their real tier, and this only ever grants access.
  bool get isPremium => StorePolicy.unlockAllPaidFeatures || _status.premium;
  String get tier => _status.tier;
  List<BillingPlan> get plans => _plans;
  bool get loadingPlans => _loadingPlans;
  bool get busy => _busy;
  bool get awaitingReturn => _pendingSessionId != null;

  /// Look up the price-catalogue id for a tier + interval, or null if the server
  /// didn't advertise it.
  String? planId(String tier, String interval) {
    for (final p in _plans) {
      if (p.tier == tier && p.interval == interval) return p.id;
    }
    return null;
  }

  /// Pull entitlement + catalogue after sign-in (and any time we want a refresh).
  /// Failures are swallowed - billing being unreachable must never block the app.
  Future<void> refresh() async {
    try {
      _status = await _billing.status();
      notifyListeners();
    } catch (_) {/* stay on last-known status */}
  }

  Future<void> loadPlans() async {
    if (_plans.isNotEmpty || _loadingPlans) return;
    _loadingPlans = true;
    notifyListeners();
    try {
      _plans = StorePolicy.useStoreKit
          ? await _loadStorePlans()
          : await _billing.plans();
    } catch (e) {
      // Leave empty; the paywall says the store is unreachable rather than
      // rendering a card with a dash where the price goes.
      debugPrint('[premium] could not load plans: $e');
    } finally {
      _loadingPlans = false;
      notifyListeners();
    }
  }

  /// StoreKit's prices, as plans.
  ///
  /// Starting the service here rather than at app launch keeps StoreKit out of
  /// the cold-start path: the only screen that needs a price is this one, and
  /// a store round trip on every launch is a cost paid by everybody who never
  /// opens the paywall. The purchase stream still attaches before any product
  /// is queried, which is what stops a purchase completed while the app was
  /// closed from being missed.
  Future<List<BillingPlan>> _loadStorePlans() async {
    _iap.verify = _verifyWithServer;
    _iap.onEntitlementChanged = refresh;
    await _iap.start();
    _storeUnavailable = !_iap.available;
    if (_storeUnavailable) return const [];

    final out = <BillingPlan>[];
    for (final p in _iap.products) {
      final planId = IapProducts.planIdFor(p.id);
      if (planId == null) continue; // not one of ours
      out.add(BillingPlan.fromStore(
        planId: planId,
        interval: planId.endsWith('_year') ? 'year' : 'month',
        displayPrice: p.price,
        rawPrice: p.rawPrice,
        currencyCode: p.currencyCode,
      ));
    }
    return out;
  }

  /// The verification hook handed to [IapService].
  ///
  /// Returning false here is what stops the transaction being finished, so a
  /// purchase the server would not confirm stays recoverable rather than being
  /// thrown away. The status that comes back is adopted immediately: the
  /// server has just told us what this user is entitled to, so there is no
  /// reason to ask it again.
  Future<bool> _verifyWithServer(PurchaseDetails purchase) async {
    final planId = IapProducts.planIdFor(purchase.productID);
    if (planId == null) return false;
    try {
      _status = await _billing.verifyApple(
        planId: planId,
        productId: purchase.productID,
        transactionId: purchase.purchaseID ?? '',
        receipt: purchase.verificationData.serverVerificationData,
      );
      notifyListeners();
      return _status.premium;
    } catch (e) {
      debugPrint('[premium] apple verification failed: $e');
      return false;
    }
  }

  /// Buy [planId] on whichever rail is live. Throws [IapException] on iOS when
  /// the purchase does not complete, so the paywall can say why; returns false
  /// elsewhere when the browser would not open.
  Future<bool> buy(String planId) async {
    if (!StorePolicy.useStoreKit) return startCheckout(planId);
    // Thrown, not returned false.
    //
    // The paywall only reports a false on the Stripe rail, so on StoreKit a
    // false arrived as nothing at all: Subscribe did nothing, said nothing,
    // and went on doing nothing until the app was force quit. _busy stays set
    // while a purchase is in flight, and a sandbox sign-in that stalls can
    // leave it set for a minute, which is exactly when somebody taps again.
    if (_busy) throw IapException(IapFailure.alreadyRunning);

    final productId = _productIdFor(planId);
    final product = productId == null ? null : _iap.productFor(productId);
    if (product == null) throw IapException(IapFailure.unavailable);

    _busy = true;
    notifyListeners();
    try {
      await _iap.buy(product);
      // The stream verified it before completing, so entitlement is already
      // in _status. Re-reading would only risk a stale answer from a replica.
      return _status.premium;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  static String? _productIdFor(String planId) => switch (planId) {
        'pro_month' => IapProducts.proMonthly,
        'pro_year' => IapProducts.proYearly,
        _ => null,
      };

  /// Restore an earlier purchase. Apple requires this on any screen that sells
  /// a subscription, and its absence is a rejection on its own - somebody who
  /// reinstalls the app has already paid and must not be asked to pay twice.
  ///
  /// Restored transactions arrive on the same stream as new ones, so they go
  /// through the same server verification. Returns true if entitlement is now
  /// premium.
  Future<bool> restore() async {
    if (_busy) return isPremium;
    _busy = true;
    notifyListeners();
    try {
      if (StorePolicy.useStoreKit) {
        await _iap.restore();
      } else {
        // Nothing to replay on the Stripe rail: the subscription is attached
        // to the account, so re-reading status IS the restore.
        await refresh();
      }
      return _status.premium;
    } catch (e) {
      debugPrint('[premium] restore failed: $e');
      return _status.premium;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Start Checkout for [planId] (a catalogue id like 'pro_month'). Opens the
  /// hosted page in the browser. Returns true if the browser launched.
  Future<bool> startCheckout(String planId) async {
    // Refused outright where Stripe is not the rail, not merely hidden in the
    // UI. This is the call that opens an external payment page, so it is the
    // one that has to be impossible rather than unlikely - and on iOS that is
    // Guideline 3.1.1 whether or not a purchase completes there.
    if (!StorePolicy.canUseExternalCheckout) return false;
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      final res = await _billing.checkout(planId);
      final uri = Uri.parse(res.url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) {
        _pendingSessionId = res.sessionId;
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Called when the app comes back to the foreground. If a checkout was in
  /// flight, reconcile it. Returns true if the user is now premium.
  Future<bool> reconcileOnResume() async {
    final sid = _pendingSessionId;
    if (sid == null) return false;
    try {
      final s = await _billing.confirm(sid);
      _status = s;
      if (s.premium) _pendingSessionId = null; // done; stop polling
      notifyListeners();
      return s.premium;
    } catch (_) {
      return false;
    }
  }

  /// Open Stripe's hosted Billing Portal (switch plan / update card / cancel).
  /// After the portal we re-check status on resume, so a cancel or plan change
  /// reflects the moment the user returns. Returns true if the browser launched.
  Future<bool> openBillingPortal() async {
    // Also an external payment page: it can change a plan and take money, so
    // it is refused on the StoreKit rail for the same reason. iOS subscribers
    // manage theirs in Settings instead - see [manageSubscriptionUrl].
    if (!StorePolicy.canUseExternalCheckout) return false;
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      final url = await _billing.portal();
      final ok =
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      // Mark that a change may have happened so resume re-checks entitlement.
      if (ok) _awaitingPortalReturn = true;
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  bool _awaitingPortalReturn = false;

  /// Re-pull entitlement after returning from the Billing Portal (a cancel or
  /// downgrade won't have a checkout session to reconcile, so we just refresh).
  Future<void> reconcilePortalOnResume() async {
    if (!_awaitingPortalReturn) return;
    _awaitingPortalReturn = false;
    await refresh();
  }

  /// Where this user manages their subscription.
  ///
  /// Apple owns the subscription on the StoreKit rail: we cannot cancel it,
  /// change it, or even see the card, and the only honest thing to offer is
  /// the system screen that can. Apple publishes this URL for exactly that,
  /// and it opens the real Subscriptions page rather than the App Store app.
  static const appleSubscriptionsUrl =
      'https://apps.apple.com/account/subscriptions';

  /// Open Apple's Subscriptions screen. Returns true if it launched.
  Future<bool> openAppleSubscriptions() async {
    try {
      return await launchUrl(Uri.parse(appleSubscriptionsUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Put a catalogue in place without a store or a server.
  ///
  /// The paywall only renders its offer once it has prices, so without this
  /// every widget test of that screen sees the "store unreachable" state and
  /// the parts worth pinning - the price line, the restore link, the renewal
  /// notice - are never built.
  @visibleForTesting
  void debugSeedPlans(List<BillingPlan> seeded) {
    _plans = seeded;
    _loadingPlans = false;
    notifyListeners();
  }

  /// Forget the catalogue so [loadPlans] will fetch it again.
  ///
  /// [loadPlans] is deliberately a no-op once it has plans, so a retry after a
  /// store that did not answer needs the cached empty state cleared first.
  void clearPlans() {
    _plans = const [];
    _storeUnavailable = false;
    notifyListeners();
  }

  /// Give up on a pending checkout (user cancelled / navigated away for good).
  void clearPending() {
    _pendingSessionId = null;
  }
}
