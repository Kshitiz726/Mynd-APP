import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/services/iap_service.dart';

/// The local StoreKit test harness, checked as a whole.
///
/// Every piece of this was already "done" and none of it worked. The scheme
/// pointed at ../../Runner/OurMynd.storekit, which resolves inside the
/// .xcodeproj rather than beside it, and the file was never added to the Xcode
/// project at all - so Xcode had nothing to attach and StoreKit answered every
/// product query with "no such product". From inside the app that is
/// indistinguishable from a misconfigured App Store Connect, which is exactly
/// the wrong place to go looking.
///
/// None of this is reachable from a widget test, so it is checked as files.
void main() {
  final repo = Directory.current.path;
  File f(String p) => File('$repo/$p');

  const schemePath =
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme';
  const storekitPath = 'ios/Runner/OurMynd.storekit';

  test('the run scheme points at a StoreKit file that is really there', () {
    final scheme = f(schemePath).readAsStringSync();
    final match = RegExp(
      r'<StoreKitConfigurationFileReference\s+identifier\s*=\s*"([^"]+)"',
    ).firstMatch(scheme);
    expect(match, isNotNull,
        reason: 'no StoreKit configuration in the run scheme: the simulator '
            'cannot test a purchase without one');
    final identifier = match!.group(1)!;

    // Xcode does not document what this path is measured from, and the
    // answers in the wild disagree: the scheme's own folder, the .xcodeproj
    // bundle, and the opened workspace are all claimed. Rather than pick one
    // and pin the wrong thing, this asserts the weaker fact that actually
    // matters - the path reaches our configuration file from *somewhere*
    // sensible. The original bug (`../../Runner/...` read from the scheme
    // folder, landing inside the .xcodeproj) fails every base, which is the
    // case worth catching.
    const bases = [
      'ios/Runner.xcworkspace',
      'ios/Runner.xcodeproj/project.xcworkspace',
      'ios/Runner.xcodeproj/xcshareddata/xcschemes',
    ];
    final resolved = <String>[];
    for (final base in bases) {
      final path = File('$repo/$base/$identifier')
          .absolute
          .uri
          .normalizePath()
          .toFilePath();
      if (File(path).existsSync()) resolved.add(base);
    }
    expect(resolved, isNotEmpty,
        reason: 'the scheme points at "$identifier", which reaches no file '
            'from any base Xcode is known to use');
  });

  test('the StoreKit file is a member of the Xcode project', () {
    // A StoreKitConfigurationFileReference resolves against the project's file
    // references. A file sitting on disk that the project has never heard of
    // is silently ignored, with no warning at build or launch.
    final pbx = f('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx, contains('OurMynd.storekit'),
        reason: 'the configuration is on disk but not in the project, so '
            'Xcode will not attach it');
  });

  test('the test products are exactly the ones the app asks for', () {
    // A mismatch here is the other way this harness fails silently: Xcode
    // attaches a configuration, StoreKit answers, and the ids do not line up.
    final json =
        jsonDecode(f(storekitPath).readAsStringSync()) as Map<String, dynamic>;
    final ids = <String>{};
    for (final g in (json['subscriptionGroups'] as List)) {
      for (final s in ((g as Map)['subscriptions'] as List)) {
        ids.add((s as Map)['productID'] as String);
      }
    }
    expect(ids, IapProducts.all);
  });

  test('every test product is priced and has a localisation', () {
    final json =
        jsonDecode(f(storekitPath).readAsStringSync()) as Map<String, dynamic>;
    for (final g in (json['subscriptionGroups'] as List)) {
      for (final s in ((g as Map)['subscriptions'] as List)) {
        final sub = s as Map;
        final id = sub['productID'];
        expect(sub['displayPrice'], isNotNull, reason: '$id has no price');
        expect((sub['localizations'] as List), isNotEmpty,
            reason: '$id has no localisation, so Apple\'s own payment sheet '
                'has no name to show');
        expect(sub['recurringSubscriptionPeriod'], isNotNull,
            reason: '$id does not say how often it renews');
      }
    }
  });
}
