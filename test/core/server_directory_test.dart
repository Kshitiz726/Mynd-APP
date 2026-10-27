import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/api_config.dart';
import 'package:ourmynd/core/services/server_directory.dart';

/// The rules that decide where this app sends its session token.
///
/// [ServerDirectory.normalise] is the only gate between a file on a website and
/// the address every authenticated request goes to, so each rule it enforces is
/// pinned here rather than left to a reading of the code. If one of these ever
/// starts failing, the failure is a security regression and not a style nit.
void main() {
  group('what the app will accept from servers.json', () {
    test('an allowed https origin passes through unchanged', () {
      expect(
        ServerDirectory.normalise('https://ourmynd-server-3bvh.onrender.com'),
        'https://ourmynd-server-3bvh.onrender.com',
      );
    });

    test('http is never followed, not even on an allowed host', () {
      // A downgrade would put the bearer token on the wire in clear text.
      expect(
        ServerDirectory.normalise('http://ourmynd-server-3bvh.onrender.com'),
        isNull,
      );
    });

    test('a host outside the allowlist is ignored', () {
      // The whole point of the fence: a stolen website cannot redirect anyone.
      expect(ServerDirectory.normalise('https://evil.example.com'), isNull);
    });

    test('an unrelated Render service is refused', () {
      // onrender.com is shared hosting, so a suffix rule would have accepted
      // anything anybody stood up there. This is the hole that closes.
      expect(ServerDirectory.normalise('https://harvester.onrender.com'), isNull);
      expect(
        ServerDirectory.normalise('https://ourmynd-server-evil.onrender.com'),
        isNull,
      );
    });

    test('both of our own Render services are allowed', () {
      // The old one stays on the list so the server can be switched back.
      expect(
        ServerDirectory.normalise('https://ourmynd-server.onrender.com'),
        'https://ourmynd-server.onrender.com',
      );
      expect(
        ServerDirectory.normalise('https://ourmynd-server-3bvh.onrender.com'),
        'https://ourmynd-server-3bvh.onrender.com',
      );
    });

    test('a lookalike host does not slip past the suffix match', () {
      // `evil-ourmynd.com` ends with "ourmynd.com" as a string. It must not
      // match, which is why the check is anchored on a dot.
      expect(ServerDirectory.normalise('https://evil-ourmynd.com'), isNull);
      expect(ServerDirectory.normalise('https://ourmynd.com.evil.net'), isNull);
    });

    test('a real subdomain of an allowed host is accepted', () {
      expect(
        ServerDirectory.normalise('https://api.ourmynd.com'),
        'https://api.ourmynd.com',
      );
    });

    test('a path, query or fragment is stripped to the bare origin', () {
      // Anything kept here would be prefixed onto every endpoint the app calls.
      expect(
        ServerDirectory.normalise(
            'https://api.ourmynd.com/evil/prefix?x=1#frag'),
        'https://api.ourmynd.com',
      );
    });

    test('credentials embedded in the address are refused outright', () {
      expect(
        ServerDirectory.normalise('https://user:pass@api.ourmynd.com'),
        isNull,
      );
    });

    test('rubbish, empty values and nulls are ignored rather than applied', () {
      expect(ServerDirectory.normalise(null), isNull);
      expect(ServerDirectory.normalise(''), isNull);
      expect(ServerDirectory.normalise('   '), isNull);
      expect(ServerDirectory.normalise('not a url'), isNull);
      expect(ServerDirectory.normalise('ftp://api.ourmynd.com'), isNull);
      expect(ServerDirectory.normalise('//api.ourmynd.com'), isNull);
    });

    test('the host is lowercased so case cannot dodge the allowlist', () {
      expect(
        ServerDirectory.normalise('https://API.OurMynd.COM'),
        'https://api.ourmynd.com',
      );
    });

    test('surrounding whitespace is tolerated', () {
      expect(
        ServerDirectory.normalise('  https://api.ourmynd.com  '),
        'https://api.ourmynd.com',
      );
    });
  });

  group('when the file is consulted at all', () {
    test('a release build follows the file', () {
      // compiledApi is https in any build that did not override it with a
      // dart-define, which is every build that ships.
      expect(Uri.parse(ApiConfig.compiledApi).scheme, 'https');
      expect(ServerDirectory.followsFile, isTrue);
    });

    test('the fallback address is the server that is actually running', () {
      // A phone that has never reached the website uses this, so it must not
      // be left pointing at a host that has been retired.
      expect(ApiConfig.hostedApi, 'https://ourmynd-server-3bvh.onrender.com');
    });

    test('the file url is the live one unless a build overrides it', () {
      expect(ServerDirectory.fileUrl, 'https://www.ourmynd.com/servers.json');
    });

    test('launch is never held up for long by a slow website', () {
      expect(ServerDirectory.fetchTimeout.inSeconds, lessThanOrEqualTo(3));
    });
  });
}
