import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/services/mail_service.dart';
import 'package:ourmynd/core/services/turn_context.dart';
import 'package:ourmynd/providers/calendar_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// A fake inbox. The real one opens a TLS socket to Gmail, which a unit test
/// must not do; what is under test here is everything between "they asked" and
/// "the model was told", which is the part that was silently broken.
class _FakeMail extends MailService {
  _FakeMail({this.connected = true, this.messages = const [], this.fail = false})
      : super.forTesting();

  final bool connected;
  final List<MailSummary> messages;
  final bool fail;

  @override
  bool get isConnected => connected;
  @override
  bool get canRead => connected;
  @override
  bool get canSend => connected;

  @override
  Future<List<MailSummary>> recent({int limit = 12, bool unreadOnly = false}) async {
    if (fail) throw const MailReadException('BAD Could not parse command');
    return unreadOnly ? messages.where((m) => m.unread).toList() : messages;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final inbox = [
    const MailSummary(
      from: 'Priya <priya@work.com>',
      subject: 'Contract needs your signature by Friday',
      date: '2026-09-23T09:00:00Z',
      snippet: 'Hi, could you sign and return the attached before Friday.',
      unread: true,
    ),
    const MailSummary(
      from: 'Newsletter',
      subject: 'Your weekly digest',
      date: '2026-09-22T09:00:00Z',
      snippet: 'Ten things you missed.',
      unread: false,
    ),
  ];

  Future<TurnContext> ask(String text) => gatherTurnContext(
        text,
        tasks: TaskProvider(),
        calendar: CalendarProvider(),
      );

  tearDown(MailService.resetInstance);

  test('asking for a summary puts the real inbox in the prompt', () async {
    MailService.instance = _FakeMail(messages: inbox);

    final ctx = await ask('can you summarize my emails');

    expect(ctx.mail, isNotNull, reason: 'the turn was not recognised as about mail');
    expect(ctx.mail, contains('Contract needs your signature'));
    expect(ctx.mail, contains('1 unread of 2'));
    // And it is told what to do with it, not just handed a list.
    expect(ctx.mail, contains('Lead with what actually needs them'));
  });

  test('"anything unread" asks for the unread ones only', () async {
    MailService.instance = _FakeMail(messages: inbox);

    final ctx = await ask('anything unread in my inbox?');

    expect(ctx.mail, contains('unread only'));
    expect(ctx.mail, contains('Contract needs your signature'));
    expect(ctx.mail, isNot(contains('Your weekly digest')),
        reason: 'a message already dealt with was offered as news');
  });

  test('a failed read says so instead of claiming an empty inbox', () async {
    // The whole point of the IMAP fix: a broken read used to come back as an
    // empty list, and the coach reported "nothing came back from your mail" on
    // a full inbox - which sends somebody to check their Gmail settings.
    MailService.instance = _FakeMail(fail: true);

    final ctx = await ask('summarise my email');

    expect(ctx.mail, contains('could not be reached'));
    expect(ctx.mail, isNot(contains('empty')));
  });

  test('a genuinely empty inbox is reported as empty', () async {
    MailService.instance = _FakeMail(messages: const []);

    final ctx = await ask('what is in my inbox');

    expect(ctx.mail, contains('empty'));
  });

  test('no account connected points at where to connect one', () async {
    MailService.instance = _FakeMail(connected: false);

    final ctx = await ask('read me my emails');

    expect(ctx.mail, contains('Connections'));
  });

  test('a turn that is not about mail does not touch the inbox', () async {
    // Nobody asking for a pep talk should have their last twelve emails sent
    // to a model as a side effect.
    MailService.instance = _FakeMail(messages: inbox);

    final ctx = await ask('i feel completely stuck today');

    expect(ctx.mail, isNull);
  });
}
