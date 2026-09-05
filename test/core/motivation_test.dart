import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ourmynd/models/motivation.dart';
import 'package:ourmynd/providers/motivation_provider.dart';
import 'package:ourmynd/providers/mood_provider.dart';

MotivationLine _line(String text) =>
    MotivationLine(text: text, at: DateTime(2026, 9, 1, 9));

void main() {
  group('the picture follows the words', () {
    test('the same line always gets the same picture', () {
      expect(_line('you do not owe anyone a good day').imageSeed,
          _line('you do not owe anyone a good day').imageSeed);
    });

    test('a rewritten line gets a new picture', () {
      // The whole point of seeding on the text. Seeded on the date, a line
      // rewritten because the mood changed kept the old photograph and the
      // card looked like nothing had happened.
      expect(_line('lower the bar. meeting it is what matters now.').imageSeed,
          isNot(_line('good day to start the thing you keep almost starting.')
              .imageSeed));
    });

    test('the seed is url-safe', () {
      expect(_line('quotes "and" punctuation, plus 1 + 1 = 2?').imageSeed,
          matches(RegExp(r'^[0-9a-z]+$')));
    });

    test('fromMemory survives a round trip', () {
      final l = MotivationLine(
          text: 'a line', at: DateTime(2026, 9, 1), fromMemory: true);
      expect(MotivationLine.fromJson(l.toJson()).fromMemory, isTrue);
      // Absent means false rather than throwing, so lines written by an older
      // build still load.
      expect(
          MotivationLine.fromJson({'text': 'x', 'at': '2026-09-01T09:00:00'})
              .fromMemory,
          isFalse);
    });
  });

  group('the offline bank answers to the mood', () {
    final p = MotivationProvider();
    const cats = [MotivationCategory.goals, MotivationCategory.health];

    test('a rough day is never told to start something', () {
      final lines = p.bankLines(8, cats, Mood.rough, 'rough/8/goals');
      // The category banks are held out entirely on a rough day. Mixing them
      // in was why moving the slider barely changed anything.
      expect(lines, isNot(contains('Start it badly. Badly started is still started.')));
      expect(lines.every((l) => l.isNotEmpty), isTrue);
    });

    test('a great day is allowed to point at something', () {
      final lines = p.bankLines(6, cats, Mood.great, 'great/6/goals');
      expect(
        lines.any((l) => l.contains('start the thing you keep almost starting') ||
            l.contains('Momentum') ||
            l.contains('gets things done') ||
            l.contains('some room today')),
        isTrue,
        reason: 'a good mood should reach the lift bank',
      );
    });

    test('changing the mood changes the lines', () {
      final rough = p.bankLines(5, cats, Mood.rough, 'rough/5/goals');
      final great = p.bankLines(5, cats, Mood.great, 'great/5/goals');
      expect(rough, isNot(equals(great)));
    });

    test('the same signature gives the same lines twice', () {
      // Stability matters as much as change: the card must not reshuffle on
      // every rebuild.
      expect(p.bankLines(5, cats, Mood.okay, 'okay/5/goals'),
          p.bankLines(5, cats, Mood.okay, 'okay/5/goals'));
    });

    test('no mood at all still returns a full day of lines', () {
      expect(p.bankLines(10, cats, null, 'none/10/goals').length, 10);
    });
  });

  group('the card is told a rewrite is coming', () {
    // The loading state was real and unreachable. `busy` only covered the
    // write itself, which starts 1200ms after the mood moves and can be over
    // in a blink when the model call fails and the local bank answers, so the
    // skeleton was either never set or set for less time than it takes to see.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<MotivationProvider> onboarded() async {
      final m = MotivationProvider();
      await m.load();
      await m.save(const MotivationSettings(onboarded: true));
      return m;
    }

    testWidgets('moving the mood puts the card into its loading state at once',
        (tester) async {
      final motivation = await onboarded();
      final mood = MoodProvider();
      await tester.pump();
      motivation.bindMood(mood);

      expect(motivation.working, isFalse);
      await mood.checkIn(Mood.rough);
      // Synchronously, on the notification. Not after the debounce, which is
      // the second the person spends looking at an unchanged card wondering
      // whether the app registered what they did.
      expect(motivation.working, isTrue);
      motivation.dispose();
    });

    test('nothing to write means no skeleton left hanging', () async {
      // The mirror of the above. `working` promises the words are about to be
      // replaced, so every path that decides not to write has to take it back
      // down - otherwise a deferred or skipped rewrite leaves the card
      // shimmering over a line that is never going to change.
      final motivation = await onboarded();
      await motivation.refresh();
      expect(motivation.working, isFalse);
      motivation.dispose();
    });
  });

  group('lines belong to the account that asked for them', () {
    // An account switch parks the outgoing account's keys and unparks the
    // incoming one's, but it cannot reach a write that is already in flight.
    // That write comes back after the swap and persists into live keys that
    // now belong to somebody else, which is the exact bug AccountScope exists
    // to prevent, arriving by a route the swap does not see. On disk it shows
    // up as lines with no settings next to them.
    test('lines with no settings are not shown and do not stay on disk',
        () async {
      SharedPreferences.setMockInitialValues({
        'om_motivation_lines':
            '[{"text":"somebody else\'s week","at":"2026-09-01T09:00:00"}]',
        'om_motivation_written_on': '2026-09-01',
        'om_motivation_signature': 'great/10/happiness/9/1/2',
      });

      final m = MotivationProvider();
      await m.load();

      expect(m.latest, isNull);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('om_motivation_lines'), isNull);
      expect(p.getString('om_motivation_signature'), isNull);
      m.dispose();
    });

    test('an onboarded account keeps its own lines', () async {
      SharedPreferences.setMockInitialValues({
        'om_motivation_settings': '{"onboarded":true,"count":10}',
        'om_motivation_lines':
            '[{"text":"my own week","at":"2026-09-01T09:00:00"}]',
      });

      final m = MotivationProvider();
      await m.load();

      expect(m.latest?.text, 'my own week');
      m.dispose();
    });
  });

  group('a notification is not the same thing as a change', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a provider that notifies without changing leaves the card alone',
        () async {
      // The memory provider notifies when a refresh fails, and a failing
      // refresh retries. Each of those raised the loading state and restarted
      // the debounce, so the timer was reset more often than it could fire and
      // the card shimmered indefinitely over a rewrite that never came. Seen
      // on device as a skeleton that never went away.
      final m = MotivationProvider();
      await m.load();
      await m.save(const MotivationSettings(onboarded: true));
      final mood = MoodProvider();
      m.bindMood(mood);
      await mood.checkIn(Mood.rough);
      expect(m.working, isTrue);

      // Let the rewrite it asked for run to completion.
      for (var i = 0; i < 40 && m.working; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(m.working, isFalse, reason: 'the first rewrite should finish');

      // Now the storm: notifications carrying nothing new. Checking in at the
      // mood you are already at notifies exactly as a failed memory retry
      // does, and says just as little.
      for (var i = 0; i < 5; i++) {
        await mood.checkIn(Mood.rough);
      }
      expect(m.working, isFalse);
      m.dispose();
    });
  });

  group('a request that lands mid-write is not dropped', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('the loading state always has something left to clear it', () async {
      // The launch race, exactly as it happens: the card asks for a write on
      // its first frame, and the mood finishes loading a beat later and asks
      // again. The second request used to hit the re-entrancy guard and return
      // - but `pending` had already been raised on its behalf, so nothing was
      // left to take it back down and the card sat on its skeleton for as long
      // as the app was open.
      final m = MotivationProvider();
      await m.load();
      await m.save(const MotivationSettings(onboarded: true));
      final mood = MoodProvider();
      m.bindMood(mood);

      // Start one write and ask for another while it is still running.
      final first = m.refresh(force: true);
      await mood.checkIn(Mood.great);
      await m.refresh(force: true);
      await first;

      for (var i = 0; i < 60 && m.working; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(m.working, isFalse,
          reason: 'the card must not be left loading forever');
      m.dispose();
    });
  });

  group('a line keeps what it came with', () {
    test('attaching a picture does not drop the attribution', () {
      // It did. The photograph was attached by rebuilding every line through
      // the constructor, so the field added last - the person who said it -
      // was simply not carried across, and every quotation reached the card
      // unattributed.
      final l = MotivationLine(
        text: 'The unexamined life is not worth living.',
        at: DateTime(2026, 9, 4, 9),
        author: 'Socrates',
        category: MotivationCategory.selfEsteem,
        fromMemory: true,
      );
      final withPicture = l.copyWith(imageUrl: 'https://example.test/a.jpg');

      expect(withPicture.imageUrl, 'https://example.test/a.jpg');
      expect(withPicture.author, 'Socrates');
      expect(withPicture.text, l.text);
      expect(withPicture.at, l.at);
      expect(withPicture.category, l.category);
      expect(withPicture.fromMemory, isTrue);
    });

    test('the attribution survives being written to disk and read back', () {
      final l = MotivationLine(
        text: 'Well begun is half done.',
        at: DateTime(2026, 9, 4, 9),
        author: 'Aristotle',
      );
      expect(MotivationLine.fromJson(l.toJson()).author, 'Aristotle');
      // A line the app wrote itself carries no name, and must not gain one.
      expect(
          MotivationLine.fromJson({'text': 'x', 'at': '2026-09-04T09:00:00'})
              .author,
          isNull);
    });
  });
}
