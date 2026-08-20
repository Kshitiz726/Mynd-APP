import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/billing_service.dart';

/// Owns the user's subscription entitlement and the checkout flow.
///
/// The whole app reads [isPremium] from here to gate premium-only features
/// (dark mode, and whatever else follows). Buying goes through Stripe's hosted
/// Checkout: we open the URL in the system browser, and when the app returns to
/// the foreground we ask the server to reconcile the session - so entitlement
/// flips on without any native billing SDK or webhook plumbing in dev.
class PremiumProvider extends ChangeNotifier {
  final _billing = BillingService.instance;

  BillingStatus _status = BillingStatus.free;
  List<BillingPlan> _plans = const [];
  bool _loadingPlans = false;
  bool _busy = false; // a checkout is mid-flight

  /// The Checkout session we're waiting to reconcile when the app resumes.
  String? _pendingSessionId;

  BillingStatus get status => _status;
  bool get isPremium => _status.premium;
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
      _plans = await _billing.plans();
    } catch (_) {/* leave empty; the paywall shows a fallback */} finally {
      _loadingPlans = false;
      notifyListeners();
    }
  }

  /// Start Checkout for [planId] (a catalogue id like 'pro_month'). Opens the
  /// hosted page in the browser. Returns true if the browser launched.
  Future<bool> startCheckout(String planId) async {
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
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      final url = await _billing.portal();
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
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

  /// Give up on a pending checkout (user cancelled / navigated away for good).
  void clearPending() {
    _pendingSessionId = null;
  }
}
