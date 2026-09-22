import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/turn_context.dart';

/// What makes a turn reach for somebody's inbox.
///
/// This is the highest-stakes matcher in the app. A false positive sends the
/// headers and snippets of a dozen private emails to a model because somebody
/// said the word "mail" in passing; a false negative costs one clarifying
/// question. The asymmetry is the whole design, so the cases that must NOT
/// match get more tests than the ones that must.
void main() {
  group('wantsMail', () {
    test('the ways people actually ask', () {
      for (final q in [
        'what is in my inbox?',
        "summarise my email",
        'summarize my emails please',
        'anything unread?',
        'check gmail for me',
        'who has emailed me today',
        'any mail from the landlord?',
        'read my mailbox',
      ]) {
        expect(wantsMail(q), isTrue, reason: '"$q" should have matched');
      }
    });

    test('talking around it does not count', () {
      for (final q in [
        'i am overwhelmed',
        'plan my morning',
        'i need to post a letter',
        'male friends keep asking me out',
        'can you help me draft something',
        'i feel like everything is piling up',
        'my male colleague said something odd',
      ]) {
        expect(wantsMail(q), isFalse,
            reason: '"$q" must NOT pull somebody\'s inbox');
      }
    });
  });

  group('wantsCalendar', () {
    test('the ways people ask about their day', () {
      for (final q in [
        'what does my day look like',
        'summarise my calendar',
        'what is on my schedule',
        'do i have any meetings today',
        'am i busy this afternoon',
        'any free time tomorrow?',
        'what is my week like',
        'whats on today',
      ]) {
        expect(wantsCalendar(q), isTrue, reason: '"$q" should have matched');
      }
    });

    test('ordinary talk does not drag the calendar in', () {
      for (final q in [
        'i am stuck',
        'hype me up',
        'i cannot start this task',
        'tell me a joke',
      ]) {
        expect(wantsCalendar(q), isFalse, reason: '"$q" should not have');
      }
    });
  });

  test('a turn about neither gathers nothing', () {
    const t = TurnContext();
    expect(t.isEmpty, isTrue);
    expect(t.promptBlock, isEmpty);
  });

  test('a gathered block tells the model it is live and not to read it out',
      () {
    const t = TurnContext(mail: 'THEIR INBOX\n- a: "b" - c');
    expect(t.isEmpty, isFalse);
    expect(t.promptBlock, contains('THEIR INBOX'));
    expect(t.promptBlock, contains('never'));
    expect(t.promptBlock, contains('Summarise'));
  });

  test('both blocks come through together when both were asked for', () {
    const t = TurnContext(mail: 'THEIR INBOX\nx', calendar: 'THEIR DAY\ny');
    expect(t.promptBlock, contains('THEIR INBOX'));
    expect(t.promptBlock, contains('THEIR DAY'));
  });
}
