import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/mail_service.dart';
import 'package:ourmynd/core/services/mail_watch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A message queued for later has to go by itself.
///
/// The whole value of scheduling is that nobody has to be present at the
/// moment. A queued send that stopped to ask permission, or that quietly
/// dropped itself when the send failed, would be worse than not offering the
/// feature: the person believes it went and it did not.
class _FakeMail extends MailService {
  _FakeMail({this.ok = true}) : super.forTesting();

  final bool ok;
  final List<String> sent = [];

  @override
  bool get isConnected => true;

  @override
  Future<MailResult> send({
    required String to,
    required String subject,
    required String body,
  }) async {
    sent.add(to);
    return ok
        ? MailResult.success('Sent to $to.')
        : const MailResult.failure('The server refused it.');
  }
}

ScheduledMail at(DateTime when, {String to = 'sam@example.com', String? id}) =>
    ScheduledMail(
      id: id ?? 'q-${when.microsecondsSinceEpoch}',
      to: to,
      subject: 'Morning',
      body: 'Hello there.',
      at: when,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(MailService.resetInstance);

  test('a message whose time has passed goes without being asked', () async {
    final mail = _FakeMail();
    MailService.instance = mail;
    final w = MailWatch.instance;

    await w.scheduleSend(
        at(DateTime.now().subtract(const Duration(minutes: 1))));

    expect(mail.sent, ['sam@example.com'],
        reason: 'a queued message must send itself, with nobody present');
    expect(w.queue, isEmpty, reason: 'it should be off the queue once sent');
  });

  test('a message still in the future is left alone', () async {
    final mail = _FakeMail();
    MailService.instance = mail;
    final w = MailWatch.instance;
    for (final m in w.queue.toList()) {
      await w.cancelSend(m.id);
    }

    await w.scheduleSend(at(DateTime.now().add(const Duration(hours: 3))));

    expect(mail.sent, isEmpty, reason: 'it went early');
    expect(w.queue, hasLength(1));
  });

  test('a failed send stays queued rather than vanishing', () async {
    final mail = _FakeMail(ok: false);
    MailService.instance = mail;
    final w = MailWatch.instance;
    for (final m in w.queue.toList()) {
      await w.cancelSend(m.id);
    }

    await w.scheduleSend(
        at(DateTime.now().subtract(const Duration(minutes: 1)), id: 'keeper'));

    expect(mail.sent, hasLength(1), reason: 'it should have been attempted');
    expect(w.queue.map((m) => m.id), contains('keeper'),
        reason: 'a message lost on a failed send is the worst outcome here: '
            'nobody finds out it never arrived');
  });

  test('cancelling takes it out of the queue', () async {
    MailService.instance = _FakeMail();
    final w = MailWatch.instance;
    for (final m in w.queue.toList()) {
      await w.cancelSend(m.id);
    }

    await w.scheduleSend(
        at(DateTime.now().add(const Duration(hours: 2)), id: 'gone'));
    expect(await w.cancelSend('gone'), isTrue);
    expect(w.queue, isEmpty);
    expect(await w.cancelSend('gone'), isFalse,
        reason: 'cancelling twice should say it found nothing');
  });
}
