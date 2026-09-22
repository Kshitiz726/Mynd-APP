import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/reminder_intent.dart';
import 'package:ourmynd/models/reminder.dart';

void main() {
  group('parseReminderIntents', () {
    test('reads a reminder the coach agreed to set', () {
      final got = parseReminderIntents(
        "Done - I'll nudge you. [[remind: 14:30 | take the washing out | once]]",
      );
      expect(got.length, 1);
      expect(got.first.title, 'take the washing out');
      expect(got.first.hour, 14);
      expect(got.first.minute, 30);
      expect(got.first.repeat, ReminderRepeat.once);
    });

    test('reads more than one from a single reply', () {
      final got = parseReminderIntents(
        '[[remind: 09:00 | meds | daily]] and [[remind: 18:15 | gym | once]]',
      );
      expect(got.length, 2);
      expect(got[0].repeat, ReminderRepeat.daily);
      expect(got[1].title, 'gym');
    });

    // The point of the strictness. The coach talks about reminders constantly,
    // and prose that merely mentions one must never set one.
    test('ignores the coach talking about reminders', () {
      const chat = 'I can remind you at 14:30 if you like. Want me to? '
          'Just say remind me at 9.';
      expect(parseReminderIntents(chat), isEmpty);
    });

    test('drops a clock reading that cannot exist', () {
      expect(parseReminderIntents('[[remind: 25:00 | nope | once]]'), isEmpty);
      expect(parseReminderIntents('[[remind: 10:75 | nope | once]]'), isEmpty);
    });

    test('drops a reminder with no title', () {
      expect(parseReminderIntents('[[remind: 10:00 |   | once]]'), isEmpty);
    });

    test('an unknown repeat falls back to once, never to recurring', () {
      // Erring towards daily would mean a model typo giving somebody an alarm
      // every morning that they never asked for and have to hunt down.
      final got = parseReminderIntents('[[remind: 07:00 | x | weekly]]');
      expect(got, isEmpty);
    });
  });

  group('stripReminderMarkers', () {
    test('the user never sees the machinery', () {
      const raw = "Sorted. [[remind: 14:30 | washing | once]] Anything else?";
      final out = stripReminderMarkers(raw);
      expect(out.contains('remind:'), isFalse);
      expect(out.contains('[['), isFalse);
      expect(out, 'Sorted. Anything else?');
    });

    test('leaves a reply that has no marker alone', () {
      const raw = 'Want me to set one?';
      expect(stripReminderMarkers(raw), raw);
    });

    test('a reply that is only a marker comes back empty, not blank-padded',
        () {
      expect(stripReminderMarkers('[[remind: 08:00 | meds | daily]]'), '');
    });
  });

  test('a parsed intent becomes a reminder the app can schedule', () {
    final intent =
        parseReminderIntents('[[remind: 06:05 | stretch | daily]]').single;
    final r = intent.toReminder();
    expect(r.title, 'stretch');
    expect(r.hour, 6);
    expect(r.minute, 5);
    expect(r.repeat, ReminderRepeat.daily);
    expect(r.enabled, isTrue);
    expect(r.id, isNotEmpty);
  });
}
