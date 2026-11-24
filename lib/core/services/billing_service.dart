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
    this.displayPrice,
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

  /// The price already formatted by the store, when the store formats it.
  ///
  /// StoreKit hands back a string localised for the viewer's storefront, and
  /// Apple requires that exact string to be what the paywall shows. Our own
  /// [priceText] cannot reproduce it: it knows three currency symbols, puts
  /// them all in front, and has no idea that most of the world writes
  /// "1.200 Ft" or "R$ 19,90". So when the store gives us a price, we use it
  /// verbatim and keep [amount] only for the savings arithmetic.
  final String? displayPrice;

  /// A StoreKit product as a plan, so the paywall renders one shape whichever
  /// rail is selling.
  ///
  /// [id] is our own catalogue id rather than Apple's product id, because that
  /// is what the server records a subscription against on either rail.
  factory BillingPlan.fromStore({
    required String planId,
    required String interval,
    required String displayPrice,
    required double rawPrice,
    required String currencyCode,
  }) =>
      BillingPlan(
        id: planId,
        tier: 'pro',
        interval: interval,
        // Apple gives a decimal major-unit price; the rest of this class is in
        // minor units because that is what Stripe sends.
        amount: (rawPrice * 100).round(),
        currency: currencyCode.toLowerCase(),
        displayPrice: displayPrice,
      );

  factory BillingPlan.fromJson(Map<String, dynamic> j) => BillingPlan(
        id: j['id'] as String,
        tier: j['tier'] as String,
        interval: j['interval'] as String,
        amount: j['amount'] as int?,
        currency: j['currency'] as String?,
      );

  static const _symbols = {'gbp': '£', 'usd': r'$', 'eur': '€'};

  /// The currency symbol for [currency], defaulting to the code itself.
  String get symbol =>
      _symbols[currency ?? ''] ?? ((currency ?? '').toUpperCase());

  /// "£9.99" - the amount alone, no interval suffix. Empty when unknown.
  String get priceText {
    final store = displayPrice;
    if (store != null && store.isNotEmpty) return store;
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

  static const free =
      BillingStatus(premium: false, tier: 'free', status: 'canceled');

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

  /// Hands Apple's transaction to the server to be checked against the App
  /// Store Server API, and returns the entitlement the server then believes in.
  ///
  /// The client never decides this. A verification that ran on the device is a
  /// verification anybody with a jailbroken phone can forge, so the receipt
  /// goes to the server and the server's answer is the only one that counts.
  Future<BillingStatus> verifyApple({
    required String planId,
    required String productId,
    required String transactionId,
    required String receipt,
  }) async {
    final j = await _api.post('/api/billing/apple/verify', {
      'planId': planId,
      'productId': productId,
      'transactionId': transactionId,
      'receipt': receipt,
    });
    return BillingStatus.fromJson(j);
  }

  /// Opens Stripe's hosted Billing Portal for the current customer (switch plan,
  /// update card, or cancel). Returns the URL to launch in the browser.
  Future<String> portal() async {
    final j = await _api.post('/api/billing/portal', const {});
    return j['url'] as String;
  }
}
