import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/mail_service.dart';
import 'package:ourmynd/core/services/session_store.dart';

/// Is the Gmail connection real?
///
/// The coach was still offering to draft rather than send, which is the exact
/// wording of the "no account is connected" branch of its prompt. That branch
/// is chosen from one boolean, so either the connection did not survive, or
/// the grant was never given and the connect screen said it was.
///
/// Both are invisible from the outside: the screen shows an address either
/// way. This prints what the app actually believes, and then tries to use the
/// grant, because a stored address with a refused scope looks exactly like a
/// working connection until the moment something is sent.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('what the app believes about the mail account', (tester) async {
    debugPrint('[mail] session restored: ${await SessionStore.restore()}');

    final m = MailService.instance;
    await m.init();

    final addr = m.address;
    // Masked: this lands in a log, and the local part is the identifying half.
    final shown = addr == null
        ? 'NONE'
        : '${addr[0]}***@${addr.split('@').last}';

    debugPrint('[mail] isConnected: ${m.isConnected}');
    debugPrint('[mail] isOauth:     ${m.isOauth}');
    debugPrint('[mail] address:     $shown');

    if (!m.isConnected) {
      debugPrint('[mail] VERDICT: nothing is connected, so the coach is '
          'correctly saying it can only draft.');
      return;
    }

    // A stored address proves somebody pressed connect. It does not prove
    // Google granted the scopes, and the restricted ones need a verified
    // client. Reading is the cheap half of the grant to test.
    try {
      final msgs = await m.recent(limit: 3);
      debugPrint('[mail] read grant works: ${msgs.length} messages back');
      for (final x in msgs) {
        debugPrint('[mail]   ${x.promptLine}');
      }
      debugPrint('[mail] VERDICT: connected and readable.');
    } catch (e) {
      debugPrint('[mail] read FAILED: $e');
      debugPrint('[mail] VERDICT: an address is stored but the grant is not '
          'usable, which is the state that looks connected and is not.');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
