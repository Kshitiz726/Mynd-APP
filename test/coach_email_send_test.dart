import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/email_approval.dart';
import 'package:ourmynd/core/services/mail_service.dart';
import 'package:ourmynd/models/chat_message.dart';
import 'package:ourmynd/providers/coach_provider.dart';
import 'package:ourmynd/providers/energy_provider.dart';
import 'package:ourmynd/providers/focus_provider.dart';
import 'package:ourmynd/providers/habit_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// From "send this to Sam" to a bubble that says whether it went.
///
/// Everything between those two points was previously provable only by
/// sending a real email from a real account with a real credential, which is
/// why it kept being wrong in ways nobody noticed: the reply reads as though
/// the message went, so a send that quietly failed actively told somebody a
/// thing had been delivered when it had not.
///
/// The transport is doubled here. What is under test is the part this app
/// owns: that a marker in a reply is executed rather than shown, that the
/// outcome reaches the conversation either way, and that a failure names the
/// reason instead of disappearing.
class _FakeMail extends MailService {
  _FakeMail({this.ok = true, this.message = 'Sent to x@y.z', this.throws = false})
      : super.forTesting();

  final bool ok;
  final String message;
  final bool throws;

  final List<({String to, String subject, String body})> sent = [];

  @override
  bool get isConnected => true;

  @override
  Future<MailResult> send({
    required String to,
    required String subject,
    required String body,
  }) async {
    sent.add((to: to, subject: subject, body: body));
    if (throws) throw StateError('the socket died');
    return ok ? MailResult.success(message) : MailResult.failure(message);
  }
}

/// A coach with the approval step already answered, unless a test is about
/// the approval step itself.
Future<CoachProvider> buildCoach({bool alwaysSend = true}) async {
  final c = CoachProvider(
    energy: EnergyProvider(),
    tasks: TaskProvider(),
    habits: HabitProvider(),
    focus: FocusProvider(),
    settings: SettingsProvider(),
  );
  if (alwaysSend) await c.setAlwaysSendMail(true);
  return c;
}

/// Let the pending approval appear, answer it, and let the send run.
Future<void> settleWith(CoachProvider coach, EmailDecision d) async {
  await pumpMicrotasks();
  expect(coach.pendingEmail, isNotNull,
      reason: 'nothing was waiting on an answer');
  coach.resolvePendingEmail(d);
  await pumpMicrotasks();
}

/// Let the send pipeline's awaits unwind.
Future<void> pumpMicrotasks() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ChatMessage reply(String text) =>
    ChatMessage(id: 'a1', text: text, fromUser: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The providers the coach is built from read preferences on construction.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(MailService.resetInstance);

  test('a marker in the reply is executed, not shown to the reader', () async {
    final mail = _FakeMail();
    MailService.instance = mail;
    final coach = await buildCoach();

    final msg = reply(
      "I'll get that over to him now. "
      '[[email: sam@example.com | Running late | Hi Sam, I am running '
      'about twenty minutes behind. See you shortly.]] '
      'Anything else you want to add?',
    );
    coach.runEmailIntents(msg);
    await pumpMicrotasks();

    // The machinery never appears in the conversation.
    expect(msg.text, isNot(contains('[[email:')));
    expect(msg.text, contains("I'll get that over to him now."));
    expect(msg.text, contains('Anything else'));

    // And it actually ran, with the writing the coach composed.
    expect(mail.sent, hasLength(1));
    expect(mail.sent.single.to, 'sam@example.com');
    expect(mail.sent.single.subject, 'Running late');
    expect(mail.sent.single.body, startsWith('Hi Sam'));
  });

  test('the conversation says it went, and to whom', () async {
    MailService.instance = _FakeMail(message: 'Sent to sam@example.com.');
    final coach = await buildCoach();

    coach.runEmailIntents(reply(
        '[[email: sam@example.com | Hi | Just saying hello.]]'));
    await pumpMicrotasks();

    final last = coach.messages.last;
    expect(last.fromUser, isFalse);
    expect(last.text, contains('Sent to sam@example.com'));
    expect(last.text, isNot(contains('Sending to')),
        reason: 'the in-flight note should have been replaced, not left');
  });

  test('a refused send says so, and says why', () async {
    MailService.instance = _FakeMail(
      ok: false,
      message: 'Your Google session expired. Open Connections and reconnect.',
    );
    final coach = await buildCoach();

    coach.runEmailIntents(reply(
        '[[email: sam@example.com | Hi | Just saying hello.]]'));
    await pumpMicrotasks();

    final last = coach.messages.last;
    expect(last.text, contains("Didn't send"));
    expect(last.text, contains('sam@example.com'));
    expect(last.text, contains('reconnect'),
        reason: 'a failure with no reason is the thing being fixed');
  });

  test('a transport that throws still reports, rather than hanging', () async {
    // send() is documented not to throw. If that is ever untrue, the bubble
    // above would sit on "Sending…" forever, which reads as in progress.
    MailService.instance = _FakeMail(throws: true);
    final coach = await buildCoach();

    coach.runEmailIntents(reply(
        '[[email: sam@example.com | Hi | Just saying hello.]]'));
    await pumpMicrotasks();

    expect(coach.messages.last.text, contains("Didn't send"));
    expect(coach.messages.last.text, isNot(contains('Sending to')));
  });

  test('two emails in one reply both go, and both are reported', () async {
    final mail = _FakeMail();
    MailService.instance = mail;
    final coach = await buildCoach();

    coach.runEmailIntents(reply(
      '[[email: a@example.com | One | First message.]]'
      '[[email: b@example.com | Two | Second message.]]',
    ));
    await pumpMicrotasks();

    expect(mail.sent.map((s) => s.to), ['a@example.com', 'b@example.com']);
    final notes =
        coach.messages.where((m) => m.text.contains('✉️')).toList();
    expect(notes, hasLength(2));
  });

  test('prose about sending an email never triggers one', () async {
    // The asymmetry that matters: a missed send costs one retry, a false
    // positive puts somebody's words in a stranger's inbox.
    final mail = _FakeMail();
    MailService.instance = mail;
    final coach = await buildCoach();

    for (final text in [
      'I can email sam@example.com for you if you like.',
      'Want me to send that to your manager?',
      'email: sam@example.com',
      '[[email: not-an-address | Hi | Hello.]]',
      '[[email: sam@example.com |  | Hello.]]',
      '[[email: sam@example.com | Subject | ]]',
    ]) {
      coach.runEmailIntents(reply(text));
    }
    await pumpMicrotasks();

    expect(mail.sent, isEmpty, reason: 'something here sent a real email');
  });

  test('the same email written twice in one reply is sent once', () async {
    // Reported: "the sent to ... message keeps sending twice". A model told
    // to write a marker will sometimes write it once mid-sentence and again
    // at the end as a summary. Nothing downstream could tell that apart from
    // somebody genuinely asking for two emails, so the recipient got two.
    final mail = _FakeMail();
    MailService.instance = mail;
    final coach = await buildCoach();

    coach.runEmailIntents(reply(
      "Sending that now. [[email: sam@example.com | Hi | Just saying hello.]] "
      'All done. [[email: sam@example.com | Hi | Just saying hello.]]',
    ));
    await pumpMicrotasks();

    expect(mail.sent, hasLength(1));
    expect(coach.messages.where((m) => m.text.contains('✉️')), hasLength(1));
  });

  test('two genuinely different emails are still both sent', () async {
    // The dedupe must key on the whole message, not just the recipient: two
    // notes to one person in a single turn is a real thing to ask for.
    final mail = _FakeMail();
    MailService.instance = mail;
    final coach = await buildCoach();

    coach.runEmailIntents(reply(
      '[[email: sam@example.com | Running late | Be there at ten past.]]'
      '[[email: sam@example.com | One more thing | Bringing the file.]]',
    ));
    await pumpMicrotasks();

    expect(mail.sent, hasLength(2));
  });

  group('asking before it sends', () {
    test('nothing leaves until somebody says so', () async {
      final mail = _FakeMail();
      MailService.instance = mail;
      final coach = await buildCoach(alwaysSend: false);

      coach.runEmailIntents(reply(
          '[[email: sam@example.com | Hi | Just saying hello.]]'));
      await pumpMicrotasks();

      expect(coach.pendingEmail, isNotNull,
          reason: 'the draft should be waiting on an answer');
      expect(mail.sent, isEmpty,
          reason: 'it sent before anybody approved it');
    });

    test('Allow sends it, and asks again next time', () async {
      final mail = _FakeMail();
      MailService.instance = mail;
      final coach = await buildCoach(alwaysSend: false);

      coach.runEmailIntents(reply(
          '[[email: sam@example.com | Hi | Just saying hello.]]'));
      await settleWith(coach, const EmailDecision.allow());

      expect(mail.sent, hasLength(1));
      expect(coach.messages.last.text, contains('Sent to sam@example.com'));
      expect(coach.alwaysSendMail, isFalse,
          reason: 'allowing one is not allowing all of them');
    });

    test('Never ask again sends it and stops asking', () async {
      final mail = _FakeMail();
      MailService.instance = mail;
      final coach = await buildCoach(alwaysSend: false);

      coach.runEmailIntents(reply(
          '[[email: a@example.com | One | First.]]'));
      await settleWith(coach, const EmailDecision.always());
      expect(mail.sent, hasLength(1));
      expect(coach.alwaysSendMail, isTrue);

      // The next one goes without a question.
      coach.runEmailIntents(reply(
          '[[email: b@example.com | Two | Second.]]'));
      await pumpMicrotasks();
      expect(coach.pendingEmail, isNull);
      expect(mail.sent, hasLength(2));
    });

    test('declining sends nothing and says the draft is still there',
        () async {
      final mail = _FakeMail();
      MailService.instance = mail;
      final coach = await buildCoach(alwaysSend: false);

      coach.runEmailIntents(reply(
          '[[email: sam@example.com | Hi | Just saying hello.]]'));
      await settleWith(coach, const EmailDecision.cancel());

      expect(mail.sent, isEmpty);
      expect(coach.messages.last.text, contains('Not sent'));
    });

    test('changing something asks again before anything is sent', () async {
      // The revision itself needs a model, which is not reachable from a unit
      // test, so the draft comes back unchanged. What matters here is the
      // control flow: a change must put the draft back in front of them rather
      // than sending either version.
      final mail = _FakeMail();
      MailService.instance = mail;
      final coach = await buildCoach(alwaysSend: false);

      coach.runEmailIntents(reply(
          '[[email: sam@example.com | Hi | Just saying hello.]]'));
      await pumpMicrotasks();

      coach.resolvePendingEmail(const EmailDecision.change('make it shorter'));
      await pumpMicrotasks();

      expect(mail.sent, isEmpty,
          reason: 'a change must not send anything on its own');
      expect(coach.pendingEmail, isNotNull,
          reason: 'the revised draft has to be approved in its turn');

      coach.resolvePendingEmail(const EmailDecision.allow());
      await pumpMicrotasks();
      expect(mail.sent, hasLength(1));
    });

    test('an empty change instruction just asks again', () async {
      final mail = _FakeMail();
      MailService.instance = mail;
      final coach = await buildCoach(alwaysSend: false);

      coach.runEmailIntents(reply(
          '[[email: sam@example.com | Hi | Just saying hello.]]'));
      await pumpMicrotasks();

      coach.resolvePendingEmail(const EmailDecision.change('   '));
      await pumpMicrotasks();

      expect(coach.pendingEmail, isNotNull);
      expect(mail.sent, isEmpty);
    });
  });
}
