import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Apple's product identifiers, exactly as they are typed in App Store
/// Connect.
///
/// A product id is permanent there: it can never be edited and never reused,
/// even after the subscription is deleted. So these strings are the one thing
/// in the purchase path that cannot be fixed later, and they are kept here
/// rather than inline so there is a single place to check them against the
/// dashboard.
abstract final class IapProducts {
  static const proMonthly = 'com.ourmynd.app.pro.monthly';
  static const proYearly = 'com.ourmynd.app.pro.yearly';

  static const all = <String>{proMonthly, proYearly};

  /// The plan id our own server knows this product by, so a verified purchase
  /// can be recorded against the same catalogue Stripe writes to.
  static String? planIdFor(String productId) => switch (productId) {
        proMonthly => 'pro_month',
        proYearly => 'pro_year',
        _ => null,
      };
}

/// Why a purchase did not complete, in words meant for the person.
enum IapFailure {
  /// They backed out. Not an error, and must not be reported as one.
  cancelled,

  /// The device is not allowed to buy (parental controls, managed device).
  notAllowed,

  /// Products could not be loaded, or the store is unreachable.
  unavailable,

  /// Apple took the payment but our server would not confirm it.
  notVerified,

  other,
}

class IapException implements Exception {
  IapException(this.failure, [this.detail]);
  final IapFailure failure;
  final String? detail;

  /// What to put on screen. Deliberately not the raw StoreKit message, which
  /// is written for a developer reading a console.
  String get message => switch (failure) {
        IapFailure.cancelled => 'Purchase cancelled.',
        IapFailure.notAllowed =>
          'This device is not allowed to make purchases.',
        IapFailure.unavailable =>
          'The App Store is not reachable right now. Try again in a moment.',
        IapFailure.notVerified =>
          'Your purchase went through, but we could not confirm it yet. It '
              'will unlock shortly - contact support@ourmynd.com if it does '
              'not.',
        IapFailure.other => 'That purchase could not be completed.',
      };

  @override
  String toString() =>
      'IapException(${failure.name}${detail == null ? '' : ': $detail'})';
}

/// StoreKit, wrapped.
///
/// Deliberately thin, and deliberately not the source of truth. Entitlement
/// is decided by our own server and read through PremiumProvider; all this
/// does is run Apple's purchase flow and hand the resulting transaction over
/// to be verified. A client that decides for itself whether it has paid is a
/// client anybody can lie to.
///
/// The purchase stream is the only place a completed purchase arrives, for
/// either of two reasons: StoreKit delivers purchases that finished while the
/// app was closed, and it re-delivers anything that was never finished. So
/// buying is "start a purchase and wait for the stream to speak", not "await
/// a function that returns the result".
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  // A getter for the same reason PremiumProvider's is: InAppPurchase.instance
  // registers a platform and, on Android, opens a billing connection the
  // moment it is first read. Nothing here should happen because the singleton
  // exists - only because something called into it.
  InAppPurchase get _iap => InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  List<ProductDetails> _products = const [];

  /// What the store says these cost, already formatted in the viewer's own
  /// currency by StoreKit. Never formatted by us: Apple decides the price in
  /// each storefront, and a hardcoded "£6.99" is wrong in most of the world.
  List<ProductDetails> get products => _products;

  bool _available = false;

  /// False where there is no store at all, which includes a simulator with no
  /// StoreKit configuration file selected.
  bool get available => _available;

  /// Called when a purchase is verified and entitlement should be re-read.
  void Function()? onEntitlementChanged;

  /// Hands a completed purchase to the server for verification. Returns true
  /// when the server accepted it. Injected rather than imported so that this
  /// file has no opinion about the API client, and so tests can drive the
  /// whole flow without a network.
  Future<bool> Function(PurchaseDetails purchase)? verify;

  Future<void> start() async {
    _available = await _iap.isAvailable();
    if (!_available) {
      debugPrint('[iap] store unavailable');
      return;
    }
    // Listen before querying. A purchase that completed while the app was
    // closed is delivered as soon as the stream has a listener, and attaching
    // afterwards is how those get missed.
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('[iap] purchase stream error: $e'),
    );
    await loadProducts();
  }

  Future<void> loadProducts() async {
    final response = await _iap.queryProductDetails(IapProducts.all);
    if (response.notFoundIDs.isNotEmpty) {
      // Almost always one of three things, and worth saying which so this is
      // not debugged as "the paywall is empty": the ids do not match App
      // Store Connect, the Paid Applications agreement is not Active, or the
      // products are not yet in Ready to Submit.
      debugPrint('[iap] not found: ${response.notFoundIDs}');
    }
    _products = response.productDetails;
  }

  ProductDetails? productFor(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// How long a purchase may say nothing at all before we go looking.
  ///
  /// Generous on purpose: a real purchase takes seconds, but somebody typing
  /// an Apple ID password, or approving with Face ID after a failed attempt,
  /// can genuinely take a while, and cutting them off early would report a
  /// failure to a person who is still paying.
  @visibleForTesting
  static Duration silenceBeforeRestore = const Duration(seconds: 45);

  /// And how long after a restore to keep waiting before admitting defeat.
  @visibleForTesting
  static Duration silenceBeforeGivingUp = const Duration(seconds: 20);

  /// Start a purchase. Completes when the purchase leaves the pending state;
  /// throws [IapException] if it does not succeed.
  Future<void> buy(ProductDetails product) {
    final completer = Completer<void>();
    _pending[product.id] = completer;
    // Two independent clocks on purpose. See _rescueIfSilent for why it can
    // not simply run after the call below.
    unawaited(_startPurchase(product));
    unawaited(_rescueIfSilent(product));
    return completer.future;
  }

  /// Ask StoreKit to begin, and notice the two ways it can decline.
  Future<void> _startPurchase(ProductDetails product) async {
    try {
      // buyNonConsumable answers false when StoreKit will not even start.
      // Only the thrown case was handled, so a false simply hung.
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        _finish(product.id, IapException(IapFailure.other, 'purchase did not start'));
      }
    } catch (e) {
      _finish(product.id, IapException(IapFailure.other, '$e'));
    }
  }

  /// What to do when a purchase says nothing at all.
  ///
  /// This runs on its own clock rather than after [_startPurchase], and that
  /// is the whole point. Buying something this Apple ID is already subscribed
  /// to puts up "You're currently subscribed to this" and `buyNonConsumable`
  /// does not return until that alert is dismissed - and on some paths not
  /// even then, because there is no new transaction to report. A rescue
  /// sequenced after the call would therefore be waiting on the very thing it
  /// exists to rescue.
  ///
  /// The symptom was ugly: PremiumProvider.buy sets `busy` and clears it in a
  /// `finally`, so a future that never completes leaves Subscribe spinning
  /// and disabled until the app is restarted. No unlock, no error, nothing to
  /// tap, on the one screen where somebody is trying to pay us.
  ///
  /// Apple saying "you already have this" means the right answer is to go and
  /// fetch what they have. A restore puts the existing transaction on the
  /// same stream, it is verified like any other, and the completer resolves
  /// through the ordinary path. This is the reinstall case too: new device,
  /// same Apple ID, nothing on our server yet.
  Future<void> _rescueIfSilent(ProductDetails product) async {
    await Future<void>.delayed(silenceBeforeRestore);
    if (!_pending.containsKey(product.id)) return;

    debugPrint('[iap] no purchase event for ${product.id}; restoring instead');
    try {
      await restore();
    } catch (e) {
      debugPrint('[iap] restore after silence failed: $e');
    }

    await Future<void>.delayed(silenceBeforeGivingUp);
    if (!_pending.containsKey(product.id)) return;
    // Nothing bought and nothing owned. Say so, rather than leaving a dead
    // button behind.
    debugPrint('[iap] giving up on ${product.id}: no purchase or entitlement');
    _finish(product.id, IapException(IapFailure.other, 'no purchase or entitlement arrived'));
  }

  /// Apple requires this for any subscription, and its absence is a rejection
  /// on its own. Restored purchases arrive on the same stream as new ones.
  Future<void> restore() => _iap.restorePurchases();

  final Map<String, Completer<void>> _pending = {};

  void _finish(String productId, [Object? error]) {
    final c = _pending.remove(productId);
    if (c == null || c.isCompleted) return;
    error == null ? c.complete() : c.completeError(error);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          // Ask-to-buy, or a slow payment sheet. Nothing to do but wait.
          continue;

        case PurchaseStatus.canceled:
          _finish(purchase.productID, IapException(IapFailure.cancelled));

        case PurchaseStatus.error:
          debugPrint('[iap] error: ${purchase.error}');
          _finish(
            purchase.productID,
            IapException(IapFailure.other, purchase.error?.message),
          );

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final ok = await verify?.call(purchase) ?? false;
          if (ok) {
            onEntitlementChanged?.call();
            _finish(purchase.productID);
          } else {
            _finish(
              purchase.productID,
              IapException(IapFailure.notVerified),
            );
            // Deliberately left unfinished.
            //
            // Somebody has paid and our server did not confirm it. Finishing
            // here tells StoreKit the transaction is dealt with and it stops
            // offering it, so a server that was merely down for a minute
            // costs that person their subscription until they think to press
            // Restore. Left open, StoreKit hands it back on the next launch
            // and the verification simply happens then.
            //
            // Safe on StoreKit 2, which this plugin uses: unfinished
            // transactions are re-delivered rather than blocking the queue
            // the way StoreKit 1's did.
            continue;
          }
      }

      // Finished only once it has been accounted for.
      //
      // An unfinished transaction is re-delivered on every launch for ever,
      // so skipping this for a purchase we HAVE honoured would mean
      // re-verifying the same one indefinitely.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
