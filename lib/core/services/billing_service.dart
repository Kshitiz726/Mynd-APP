import 'api_client.dart';

/// One purchasable plan, as described by the server's catalogue. The app never
/// hard-codes a Stripe price id - it asks the server what exists and renders it.
class BillingPlan {
  const BillingPlan({
    required this.id,
    required this.tier,
    required this.interval,
    this.amount,
    this.currency,
  });

  /// e.g. 'plus_month', 'pro_year'.
  final String id;

  /// 'plus' | 'pro'.
  final String tier;

  /// 'month' | 'year'.
  final String interval;

  /// Price in minor units (pence), straight from Stripe. Null if unavailable.
  final int? amount;

  /// ISO currency code, e.g. 'gbp'. Null if unavailable.
  final String? currency;

  factory BillingPlan.fromJson(Map<String, dynamic> j) => BillingPlan(
        id: j['id'] as String,
        tier: j['tier'] as String,
        interval: j['interval'] as String,
        amount: j['amount'] as int?,
        currency: j['currency'] as String?,
      );

  static const _symbols = {'gbp': '£', 'usd': r'$', 'eur': '€'};

  /// The currency symbol for [currency], defaulting to the code itself.
  String get symbol => _symbols[currency ?? ''] ?? ((currency ?? '').toUpperCase());

  /// "£9.99" - the amount alone, no interval suffix. Empty when unknown.
  String get priceText {
    final a = amount;
    if (a == null) return '';
    final major = a / 100;
    // Whole amounts (e.g. £199) read cleaner without trailing zeros.
    final body = major == major.roundToDouble()
        ? major.toStringAsFixed(0)
        : major.toStringAsFixed(2);
    return '$symbol$body';
  }

  /// "/mo" or "/yr".
  String get intervalSuffix => interval == 'year' ? '/yr' : '/mo';
}

/// The user's current entitlement, mirrored from the server.
class BillingStatus {
  const BillingStatus({
    required this.premium,
    required this.tier,
    required this.status,
    this.interval,
    this.currentPeriodEnd,
  });

  final bool premium;
  final String tier; // free | plus | pro
  final String status; // active | trialing | canceled | ...
  final String? interval;
  final DateTime? currentPeriodEnd;

  static const free = BillingStatus(premium: false, tier: 'free', status: 'canceled');

  factory BillingStatus.fromJson(Map<String, dynamic> j) => BillingStatus(
        premium: j['premium'] == true,
        tier: (j['tier'] as String?) ?? 'free',
        status: (j['status'] as String?) ?? 'canceled',
        interval: j['interval'] as String?,
        currentPeriodEnd: j['currentPeriodEnd'] != null
            ? DateTime.tryParse(j['currentPeriodEnd'] as String)
            : null,
      );
}

/// Thin REST wrapper over the server's `/api/billing/*` endpoints.
class BillingService {
  BillingService._();
  static final BillingService instance = BillingService._();

  final _api = ApiClient.instance;

  Future<List<BillingPlan>> plans() async {
    final j = await _api.get('/api/billing/plans');
    return (j['plans'] as List)
        .map((p) => BillingPlan.fromJson((p as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<BillingStatus> status() async {
    final j = await _api.get('/api/billing/status');
    return BillingStatus.fromJson(j);
  }

  /// Opens a Stripe Checkout session for the catalogue [planId] (e.g. 'pro_year').
  /// The server resolves it to the real Stripe price id. Returns the hosted URL
  /// to launch in the browser plus the session id to reconcile with on return.
  Future<({String url, String sessionId})> checkout(String planId) async {
    final j = await _api.post('/api/billing/checkout', {'planId': planId});
    return (url: j['url'] as String, sessionId: j['sessionId'] as String);
  }

  /// Asks the server to reconcile a finished checkout against Stripe. Returns
  /// the (possibly now-premium) status.
  Future<BillingStatus> confirm(String sessionId) async {
    final j = await _api.post('/api/billing/confirm', {'sessionId': sessionId});
    return BillingStatus.fromJson(j);
  }

  /// Opens Stripe's hosted Billing Portal for the current customer (switch plan,
  /// update card, or cancel). Returns the URL to launch in the browser.
  Future<String> portal() async {
    final j = await _api.post('/api/billing/portal', const {});
    return j['url'] as String;
  }
}
