import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/api_config.dart';
import 'package:ourmynd/core/services/server_directory.dart';

/// `deploy/servers.json` is the file that tells every installed app where to
/// send its session token. It is published to the website by hand, and until
/// now it lived only there: untracked, unreviewed, and unvalidated.
///
/// The app is careful with it - anything that fails validation is ignored and
/// the current address stays - but that safety is exactly what makes a mistake
/// invisible. A typo does not break the app, it just silently does nothing, so
/// you publish a server move, nothing moves, and there is no error anywhere to
/// tell you why. These tests run the real file through the app's own validator
/// so that mistake fails here instead.
void main() {
  late Map<String, dynamic> file;

  setUpAll(() {
    final raw = File('deploy/servers.json').readAsStringSync();
    file = jsonDecode(raw) as Map<String, dynamic>;
  });

  test('every address in it is one the app will actually accept', () {
    // The validator refuses anything that is not https, is not a host we own,
    // or carries a path or credentials. An address it refuses is dead weight in
    // the file: published, and ignored.
    for (final key in ['primary', 'api', 'secondary']) {
      final value = file[key];
      if (value == null) continue;
      expect(ServerDirectory.normalise(value as String), isNotNull,
          reason: '"$key" ($value) would be silently ignored by the app');
    }
  });

  test('it names exactly one server', () {
    // candidates() is the same function the app uses to build its probe order,
    // so this asserts the real behaviour rather than re-reading the keys.
    //
    // One, deliberately. The failover machinery still exists and still works,
    // but a standby is only worth listing when it shares the database and the
    // JWT secret with the primary. These two do not, so falling over to the
    // other one would sign every user out rather than save them, and listing
    // it would also wake a suspended instance on every probe. Add the second
    // address back here once the secrets match.
    final order = ServerDirectory.candidates(file);

    expect(order, hasLength(1),
        reason: 'one server runs at a time');
    expect(order.single, 'https://ourmynd-server.onrender.com');
  });

  test('the compiled fallback agrees with the primary', () {
    // A phone that has never reached the file uses the compiled address. If the
    // two disagree, fresh installs start on one server and everybody else is on
    // the other, which is the failover bug by a different route.
    expect(ServerDirectory.candidates(file).first, ApiConfig.hostedApi);
  });

  test('the duplicate api key collapses rather than probing twice', () {
    // `api` is the spelling build 20 and the status page read, so it is kept
    // for them and set to the same host as `primary`. The app de-duplicates, so
    // this costs nothing - but if someone later edits one and not the other,
    // the list grows to three and this fails.
    expect(file['api'], file['primary'],
        reason: 'api and primary must name the same server');
  });

  test('it explains itself to whoever opens it next', () {
    // This file gets edited in a hurry, during an outage, by someone who did
    // not write it. The note is the only documentation present at that moment.
    final help = file['help'] as String?;
    expect(help, isNotNull);
    expect(help, contains('JWT_SECRET'),
        reason: 'mismatched secrets sign every user out on failover');
    expect(help, contains('suspend'),
        reason: 'an idle standby is woken by status checks and bills hours');
  });
}
