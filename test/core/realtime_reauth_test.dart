import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/services/realtime_service.dart';

/// The socket's own expired-token recovery.
///
/// The handshake verifies an access token, and those last thirty minutes. When
/// one expired the socket just retried with it forever: ensureConnected timed
/// out and body doubling said "no connection to the focus server - try again"
/// to somebody whose session was valid and whose network was fine. Trying again
/// did nothing, because nothing on this path ever asked for a new token.
///
/// The recovery only fires if the connect error is recognised as an auth
/// failure, which makes this string the hinge of the whole fix. The server
/// rejects with `new Error('unauthorized')` - confirmed against the live server,
/// which answers exactly "unauthorized" for both a bad token and no token.
void main() {
  group('an unauthorized handshake is recognised', () {
    test('however socket.io hands the error through', () {
      // A bare message, which is what the Dart client passes today.
      expect(RealtimeService.looksUnauthorized('unauthorized'), isTrue);
      // Wrapped in a map or an exception by other transports/versions.
      expect(
        RealtimeService.looksUnauthorized({'message': 'unauthorized'}),
        isTrue,
      );
      expect(
        RealtimeService.looksUnauthorized(Exception('unauthorized')),
        isTrue,
      );
      // Case is not guaranteed anywhere in that chain.
      expect(RealtimeService.looksUnauthorized('Unauthorized'), isTrue);
      expect(RealtimeService.looksUnauthorized('HTTP 401'), isTrue);
    });

    test('and a genuine network failure is not mistaken for one', () {
      // These must NOT trigger a refresh: the token is fine, the server is not
      // reachable, and rotating a good token would be pure harm.
      expect(
        RealtimeService.looksUnauthorized('websocket error'),
        isFalse,
      );
      expect(
        RealtimeService.looksUnauthorized('timeout'),
        isFalse,
      );
      expect(
        RealtimeService.looksUnauthorized('xhr poll error'),
        isFalse,
      );
    });
  });
}
