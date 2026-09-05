import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every call to our backend has to survive an expired access token.
///
/// Access tokens last thirty minutes, so a 401 is the ordinary end of a token's
/// life, not a broken session. ApiClient always refreshed and replayed on one.
/// GroqService did not - it has its own http.Client and never went through that
/// path - so opening the app after half an hour left the feed, rooms and
/// profile working while Brain Dump, the voice capture, the goal planner and
/// the motivation card all told the user their session had expired when it had
/// not.
///
/// A source scan because the alternative is a test that has to wait out a real
/// token, and because what actually regresses is somebody adding a fifth
/// endpoint to this file and posting with the bare client like the four before
/// it did.
void main() {
  final source = File('lib/core/services/groq_service.dart').readAsStringSync();

  test('no request to our backend is sent without the 401 replay', () {
    // Bare sends: `_client.post(` / `_client.send(` not wrapped by the helper.
    final bare = <String>[];
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('_client.post(') && !line.contains('_client.send(')) {
        continue;
      }
      // Wrapped either by _withRefresh (the closure form) or by the streaming
      // path's explicit build()/refresh dance.
      final context = lines.sublist((i - 6).clamp(0, i), i + 1).join('\n');
      final wrapped = context.contains('_withRefresh(') ||
          context.contains('_client.send(build())');
      if (!wrapped) bare.add('line ${i + 1}: ${line.trim()}');
    }

    expect(
      bare,
      isEmpty,
      reason: 'These send with a possibly-expired token and never retry, so '
          'they fail for a user whose session is perfectly valid. Wrap them in '
          '_withRefresh.\n  ${bare.join('\n  ')}',
    );
  });

  test('the refresh is the shared one, not a second implementation', () {
    // Two refresh paths means two rotations racing, and the loser installs a
    // token the server has already replaced.
    expect(source, contains('ApiClient.instance.refreshSession()'));
    expect(
      File('lib/core/services/api_client.dart').readAsStringSync(),
      contains('Future<bool> refreshSession()'),
    );
  });
}
