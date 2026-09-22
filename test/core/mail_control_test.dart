import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/mail_control_intent.dart';

/// Turning the watch on, and queueing a message for later.
///
/// Both are things the coach agrees to in prose and the app then has to
/// actually do, so the join between the two is a marker in the reply. The
/// stakes are lopsided in the same direction as sending: failing to start a
/// watch costs one repeated sentence, and queueing a message nobody asked for
/// puts words in somebody's inbox at a time they did not choose.
void main() {
  group('watching', () {
    test('on and off are both recognised, either case', () {
      expect(parseWatchIntent('sure. [[watch: on]]')?.on, isTrue);
      expect(parseWatchIntent('[[WATCH: OFF]] done')?.on, isFalse);
      expect(parseWatchIntent('[[watch:on]]')?.on, isTrue);
    });

    test('talking about watching is not a marker', () {
      for (final s in [
        'i can watch your inbox if you like',
        'want me to keep an eye on your email?',
        'watch: on',
        '[[watch: maybe]]',
      ]) {
        expect(parseWatchIntent(s), isNull, reason: '"$s" should not match');
      }
    });
  });

  group('sending later', () {
    test('a full line is parsed, time and all', () {
      final out = parseScheduleIntents(
          '[[later: sam@example.com | 2026-09-23T09:15 | Morning | '
          'Hi Sam, just checking in about Friday.]]');
      expect(out, hasLength(1));
      expect(out.single.to, 'sam@example.com');
      expect(out.single.subject, 'Morning');
      expect(out.single.body, startsWith('Hi Sam'));
      expect(out.single.at, DateTime(2026, 9, 23, 9, 15));
    });

    test('a space instead of the T is accepted', () {
      final out = parseScheduleIntents(
          '[[later: a@b.co | 2026-12-01 18:30 | Later | Body here.]]');
      expect(out.single.at, DateTime(2026, 12, 1, 18, 30));
    });

    test('nonsense in the time slot queues nothing', () {
      for (final s in [
        '[[later: a@b.co | tomorrow morning | Hi | Body.]]',
        '[[later: a@b.co | 2026-13-45T99:99 | Hi | Body.]]',
        '[[later: not-an-address | 2026-09-23T09:15 | Hi | Body.]]',
        '[[later: a@b.co | 2026-09-23T09:15 |  | Body.]]',
        '[[later: a@b.co | 2026-09-23T09:15 | Hi | ]]',
      ]) {
        expect(parseScheduleIntents(s), isEmpty, reason: '"$s" queued a send');
      }
    });

    test('prose about sending later queues nothing', () {
      expect(
          parseScheduleIntents(
              "i'll send that to sam@example.com tomorrow at 9."),
          isEmpty);
    });
  });

  test('the machinery never reaches the reader', () {
    const reply = 'Right, keeping an eye on it. [[watch: on]] And that note '
        'goes out in the morning. '
        '[[later: sam@example.com | 2026-09-23T09:15 | Morning | Hi Sam.]]';
    final clean = stripMailControlMarkers(reply);
    expect(clean, isNot(contains('[[')));
    expect(clean, contains('Right, keeping an eye on it.'));
    expect(clean, contains('goes out in the morning.'));
    expect(clean, isNot(contains('  ')));
  });
}
