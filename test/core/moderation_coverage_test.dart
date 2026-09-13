import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Blocking has to hold on every surface, not most of them.
///
/// App Store Review Guideline 1.2 wants a report mechanism, a block mechanism,
/// filtering and contact details on any app with user-generated content. The
/// failure mode is not "we forgot to build it" - it is building it and missing
/// one query, so a blocked person still shows up in the comments. That is the
/// one a reviewer finds, and it is invisible to any test that only checks the
/// feed.
///
/// A source scan because these are SQL strings in a Node server that this
/// Flutter suite cannot execute. It is coarse, and it is still the difference
/// between noticing and shipping.
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('the server filters blocked users out of', () {
    test('the feed and the comment threads', () {
      final feed = read('server/src/routes/feed.ts');
      expect(feed, contains('notBlockedSql'));
      // Both listings, not just the one on the front page.
      expect(
        'notBlockedSql'.allMatches(feed).length,
        greaterThanOrEqualTo(3), // the import plus both queries
        reason: 'the comment thread needs the filter as much as the feed',
      );
    });

    test('the conversation list and the messages inside it', () {
      final chat = read('server/src/routes/chat.ts');
      expect(chat, contains('notBlockedSql'));
      expect(
        'notBlockedSql'.allMatches(chat).length,
        greaterThanOrEqualTo(3),
        reason: 'a filtered thread that still appears in the list is worse '
            'than no filter: their name sits there with nothing behind it',
      );
    });
  });

  group('blocking also stops contact, not just visibility', () {
    test('a blocked person cannot send a friend request', () {
      expect(read('server/src/routes/social.ts'), contains('isBlockedBetween'));
    });

    test('a blocked person cannot open a direct conversation', () {
      expect(read('server/src/routes/chat.ts'), contains('isBlockedBetween'));
    });
  });

  group('the four things Guideline 1.2 asks for exist', () {
    test('report and block endpoints', () {
      final m = read('server/src/routes/moderation.ts');
      expect(m, contains("r.post('/reports'"));
      expect(m, contains("r.post('/blocks'"));
      expect(m, contains("r.delete('/blocks/:userId'"));
    });

    test('and are mounted', () {
      expect(read('server/src/server.ts'), contains('moderationRouter'));
    });

    test('report and block are reachable on every surface a reviewer can reach',
        () {
      // The feed is parked out of the shell (see app_shell.dart), so the post
      // card is not where this gets tested - it is in the code, and unreachable.
      // What a reviewer CAN reach is a direct message, a focus room, and a
      // stranger they were matched with. Those carry live voice, which is the
      // situation Apple is strictest about, so those are the ones that matter.
      for (final file in [
        'lib/features/community/community_screen.dart',
        'lib/features/community/chat_screen.dart',
        'lib/features/focus/focus_room_screen.dart',
        'lib/features/focus/body_doubling_screen.dart',
      ]) {
        expect(read(file), contains('showModerationSheet'),
            reason: '$file has no way to report or block');
      }
    });

    test('a block can be undone, and support can be reached', () {
      final profile = read('lib/features/profile/profile_screen.dart');
      expect(profile, contains('BlockedAccountsScreen'),
          reason: 'a block that cannot be undone from settings is a trap: you '
              'never see their posts again, so the post is the one place the '
              'unblock button cannot live');
      expect(profile, contains('contactSupport'));
    });

    test('the account can be deleted from inside the app', () {
      // Guideline 5.1.1(v). This screen existed but had no caller anywhere -
      // the row that should have opened it opened the paywall instead.
      expect(
        read('lib/features/profile/profile_screen.dart'),
        contains('AccountDataScreen'),
      );
    });
  });
}
