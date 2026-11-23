import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:ourmynd/core/utils/om_icons.dart';

/// `OmIcons.byName` falls back to a plain circle for a name it does not know,
/// and a circle is indistinguishable from a deliberate one. Five names shipped
/// that way - including the version and licence rows on the About screen, which
/// is a screen App Review opens - and nothing failed, because nothing checked.
///
/// So this reads the source and checks every name the app actually asks for.
/// It is a source scan rather than a widget test on purpose: the names are
/// string literals spread over fifty files, and the only way to be sure none of
/// them is a typo is to look at all of them.
void main() {
  /// Every string literal passed to `byName(...)`, or to an `icon:` parameter
  /// that is later handed to it.
  Map<String, Set<String>> requestedNames() {
    final found = <String, Set<String>>{};
    final patterns = [
      RegExp(r"""byName\(\s*'([A-Za-z0-9_-]+)'\s*\)"""),
      RegExp(r"""icon:\s*'([A-Za-z0-9_-]+)'"""),
    ];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final pattern in patterns) {
        for (final match in pattern.allMatches(source)) {
          found.putIfAbsent(match.group(1)!, () => <String>{}).add(entity.path);
        }
      }
    }
    return found;
  }

  test('every icon name the app asks for exists', () {
    final requested = requestedNames();

    // Guards the scan itself: if the regexes stopped matching, an empty result
    // would pass and prove nothing.
    expect(requested.length, greaterThan(20),
        reason: 'the source scan found almost nothing, so it is probably broken');

    // `has` rather than `byName`, so every bad name is collected and reported
    // together instead of the run stopping at the first assert.
    final broken = <String, Set<String>>{
      for (final entry in requested.entries)
        if (!OmIcons.has(entry.key)) entry.key: entry.value,
    };

    expect(
      broken,
      isEmpty,
      reason: 'These names render a blank circle:\n'
          '${broken.entries.map((e) => "  '${e.key}' in ${e.value.join(', ')}").join('\n')}',
    );
  });

  test('the names that were shipping as circles now resolve', () {
    // Named one by one so a regression points at the screen it broke.
    for (final name in [
      'smartphone',
      'code',
      'checkCheck',
      'mail',
      'shield',
      'external-link',
    ]) {
      expect(OmIcons.byName(name), isNot(LucideIcons.circle), reason: name);
    }
  });
}
