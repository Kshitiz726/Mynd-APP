import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';
import 'dart:io';

import 'package:ourmynd/core/services/iap_service.dart';

/// The product ids in the app, the ids in the local StoreKit file, and the
/// ids typed into App Store Connect all have to be the same strings.
///
/// Worth a test rather than a careful read, because an Apple product id can
/// never be edited and never reused once created - a typo is not a bug you
/// fix, it is an identifier you abandon. And the failure is silent: a wrong
/// id comes back in notFoundIDs and the paywall simply renders empty.
void main() {
  test('every product maps to a plan the server already knows', () {
    for (final id in IapProducts.all) {
      expect(IapProducts.planIdFor(id), isNotNull,
          reason: '$id has no server plan id, so a verified purchase from it '
              'could not be recorded against any tier');
    }
    // Both resolve to the single paid tier.
    expect(IapProducts.planIdFor(IapProducts.proMonthly), 'pro_month');
    expect(IapProducts.planIdFor(IapProducts.proYearly), 'pro_year');
    expect(IapProducts.planIdFor('com.example.nope'), isNull);
  });

  test('the StoreKit configuration matches the ids the app asks for', () {
    // Without this the simulator silently offers nothing: StoreKit returns
    // the configured products, the app queries different strings, and the
    // paywall is blank with no error anywhere.
    final file = File('ios/Runner/OurMynd.storekit');
    expect(file.existsSync(), isTrue,
        reason: 'the local StoreKit configuration has moved');

    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final groups = doc['subscriptionGroups'] as List<dynamic>;
    expect(groups, hasLength(1),
        reason: 'one group, or Apple will let somebody hold both plans at '
            'once instead of switching between them');

    final subs = (groups.first as Map<String, dynamic>)['subscriptions']
        as List<dynamic>;
    final configured = {
      for (final s in subs) (s as Map<String, dynamic>)['productID'] as String
    };
    expect(configured, IapProducts.all);

    // Same group number, because monthly and yearly are the same tier: a
    // switch between them should be a plan change, not an upgrade.
    final levels = {
      for (final s in subs) (s as Map<String, dynamic>)['groupNumber']
    };
    expect(levels, hasLength(1));
  });

  test('a cancelled purchase is not reported as an error', () {
    // It is the single most common outcome of opening a paywall, and telling
    // somebody "that purchase could not be completed" when they chose to back
    // out reads as the app being broken.
    expect(IapException(IapFailure.cancelled).message, 'Purchase cancelled.');
    expect(IapException(IapFailure.notVerified).message,
        contains('could not confirm'));
  });
}
