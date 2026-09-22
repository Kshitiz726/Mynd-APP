import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/email_intent.dart';

/// The strictest parser in the app, and the one worth the most tests.
///
/// A mis-fired reminder is a buzz at the wrong time. A mis-fired email is a
/// message in somebody else's inbox, sent under the user's own name, that
/// cannot be recalled. Every case here is one where sending nothing is the
/// right answer.
void main() {
  group('parseEmailIntents', () {
    test('reads an email the coach agreed to send', () {
      final got = parseEmailIntents(
        "Sent. [[email: sam@example.com | Notes from today | Hi Sam, "
        "here are the notes.\n\nThanks]]",
      );
      expect(got.length, 1);
      expect(got.first.to, 'sam@example.com');
      expect(got.first.subject, 'Notes from today');
      expect(got.first.body, contains('here are the notes'));
    });

    // The whole point. The coach talks about email constantly.
    test('ignores the coach merely talking about sending one', () {
      const chat = 'I can email Sam for you if you like. Want me to send it to '
          'sam@example.com? Just say the word.';
      expect(parseEmailIntents(chat), isEmpty);
    });

    test('drops a recipient that is not an address', () {
      expect(
        parseEmailIntents('[[email: Sam | Hello | Some words here]]'),
        isEmpty,
      );
      expect(
        parseEmailIntents('[[email: sam@localhost | Hello | Some words]]'),
        isEmpty,
        reason: 'no dotted domain is not a deliverable address',
      );
    });

    test('drops an empty subject or an empty body', () {
      expect(
        parseEmailIntents('[[email: sam@example.com |   | body here]]'),
        isEmpty,
      );
      expect(
        parseEmailIntents('[[email: sam@example.com | Subject |   ]]'),
        isEmpty,
      );
    });

    test('a body may run over several lines', () {
      final got = parseEmailIntents(
        '[[email: a@b.co | Re: Friday | Line one.\nLine two.\n\nLine three.]]',
      );
      expect(got.length, 1);
      expect(got.first.body.split('\n').length, greaterThan(2));
    });

    test('reads more than one from a single reply', () {
      final got = parseEmailIntents(
        '[[email: a@b.co | One | first]] and [[email: c@d.co | Two | second]]',
      );
      expect(got.length, 2);
      expect(got[1].to, 'c@d.co');
    });
  });

  group('stripEmailMarkers', () {
    test('the user never sees the machinery', () {
      const raw = 'Done. [[email: sam@example.com | Notes | Hi Sam]] '
          'Anything else?';
      final out = stripEmailMarkers(raw);
      expect(out.contains('[['), isFalse);
      expect(out.contains('sam@example.com'), isFalse);
      expect(out, 'Done. Anything else?');
    });

    test('leaves a reply with no marker alone', () {
      const raw = 'Want me to send that?';
      expect(stripEmailMarkers(raw), raw);
    });

    test('a reply that is only a marker comes back empty', () {
      expect(
        stripEmailMarkers('[[email: a@b.co | Hi | There]]'),
        '',
      );
    });
  });
}
