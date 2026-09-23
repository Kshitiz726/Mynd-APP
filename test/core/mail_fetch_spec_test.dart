import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/mail_service.dart';

/// Every inbox read failed on a malformed IMAP command, and nobody could tell,
/// because the failure was caught and returned as an empty list. "Summarise my
/// email" answered "nothing came back" on a full inbox.
void main() {
  test('the FETCH data items are a parenthesised list', () {
    // enough_mail writes this string into the command verbatim. IMAP only
    // allows a bare data item when there is exactly one, so three items without
    // parentheses is a syntax error and Gmail answers BAD.
    expect(kFetchSpec.startsWith('('), isTrue,
        reason: 'multiple FETCH items must be parenthesised');
    expect(kFetchSpec.endsWith(')'), isTrue);
  });

  test('it asks for the three things a summary needs', () {
    expect(kFetchSpec, contains('ENVELOPE')); // who, what about, when
    expect(kFetchSpec, contains('FLAGS')); // read or unread
    expect(kFetchSpec, contains('BODY.PEEK')); // the gist
  });

  test('it peeks rather than reads', () {
    // BODY would set \Seen, so summarising an inbox would silently mark as read
    // the very messages somebody was asking about.
    expect(kFetchSpec.contains('BODY['), isFalse);
    expect(kFetchSpec, contains('BODY.PEEK[TEXT]'));
  });

  test('it takes a bounded slice of the body, not the whole thing', () {
    // A full body per message is far more of somebody's private mail than a
    // summary needs, and it is sent to a model.
    expect(kFetchSpec, contains('<0.400>'));
  });

  test('a failed read is distinguishable from an empty inbox', () {
    const e = MailReadException('BAD Could not parse command');
    expect(e.toString(), contains('BAD Could not parse command'));
  });
}
