import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/mail_service.dart';
import 'package:ourmynd/core/services/session_store.dart';
import 'package:ourmynd/core/services/turn_context.dart';
import 'package:ourmynd/providers/calendar_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// Can the coach actually see an inbox and a day?
///
/// The unit tests prove the matcher fires on the right words. They cannot
/// prove the thing that matters: that when it fires, something real comes back
/// and is shaped like something a model can answer from.
///
/// Gmail needs a connected account, so that half reports rather than fails
/// when there is none - an unconnected device is a legitimate state and the
/// block it produces ("say you cannot see it") is itself worth checking.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a turn about the day gathers a real day', (tester) async {
    expect(await SessionStore.restore(), isTrue,
        reason: 'no session on this device - sign in first');

    await MailService.instance.init();
    final tasks = TaskProvider();
    final cal = CalendarProvider();
    await tasks.load();

    final ctx = await gatherTurnContext(
      'what does my day look like',
      tasks: tasks,
      calendar: cal,
    );

    debugPrint('[e2e] calendar block:\n${ctx.calendar}');
    expect(ctx.calendar, isNotNull,
        reason: 'a turn about the day must gather the day');
    expect(ctx.calendar, contains('THEIR DAY'));
    expect(ctx.mail, isNull,
        reason: 'asking about the day must not reach into their inbox');
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('a turn about the inbox gathers mail, or says it cannot',
      (tester) async {
    expect(await SessionStore.restore(), isTrue);
    await MailService.instance.init();

    final connected = MailService.instance.isConnected;
    debugPrint('[e2e] gmail connected: $connected '
        '(oauth=${MailService.instance.isOauth})');

    final ctx = await gatherTurnContext(
      'what is in my inbox?',
      tasks: TaskProvider(),
      calendar: CalendarProvider(),
    );

    expect(ctx.mail, isNotNull);
    expect(ctx.calendar, isNull,
        reason: 'asking about mail must not pull the calendar too');
    debugPrint('[e2e] mail block:\n${ctx.mail}');

    if (!connected) {
      // The honest empty state: the model is told to say so rather than guess.
      expect(ctx.mail, contains('No email account is connected'));
      debugPrint('[e2e] NOTE: no Gmail account connected, so the live read '
          'was not exercised. Connect one in Settings to prove it.');
    } else {
      expect(ctx.mail, contains('THEIR INBOX'));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
