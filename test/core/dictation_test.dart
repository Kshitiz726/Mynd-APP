import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/live_dictation.dart';

/// The old voice path answered every failure with "didn't catch that, try
/// again" - which was wrong for a refused microphone, wrong with no network,
/// and wrong when another app held the mic. Three problems, three fixes, one
/// misleading sentence.
void main() {
  test('a refused microphone says so, and points at Settings', () {
    for (final code in ['error_permission', 'permission_denied']) {
      final msg = LiveDictation.explain(code);
      expect(msg.toLowerCase(), contains('settings'), reason: code);
      expect(msg.toLowerCase(), isNot(contains("didn't catch")));
    }
  });

  test('no network says it needs a connection', () {
    final msg = LiveDictation.explain('error_network_timeout');
    expect(msg.toLowerCase(), contains('connection'));
  });

  test('a busy microphone says what to do about it', () {
    final msg = LiveDictation.explain('error_busy');
    expect(msg.toLowerCase(), contains('busy'));
  });

  test('silence is the only thing that says it heard nothing', () {
    for (final code in ['error_no_match', 'error_speech_timeout']) {
      expect(LiveDictation.explain(code).toLowerCase(),
          contains("didn't catch"), reason: code);
    }
  });

  test('an unknown code still produces a sentence, not a code', () {
    final msg = LiveDictation.explain('error_wibble_42');
    expect(msg, isNot(contains('error_')));
    expect(msg.trim(), isNotEmpty);
  });
}
