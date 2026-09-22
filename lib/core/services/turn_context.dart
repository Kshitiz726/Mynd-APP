/// Pulling in the things a turn is about, before the turn is built.
///
/// The coach can only talk about what it is shown. "What's in my inbox" and
/// "what does my day look like" both need data that is expensive to fetch and
/// private enough that fetching it on every message would be wrong: nobody
/// asking for a pep talk should have their last twelve emails sent to a model
/// as a side effect.
///
/// So it is detected and fetched per turn. The matching is deliberately narrow
/// - the words have to be about mail or about the day - because the cost of a
/// false positive here is somebody's private mail leaving the device when they
/// did not ask for it, and the cost of a false negative is one clarifying
/// question.
library;

import 'package:flutter/foundation.dart';

import '../../providers/calendar_provider.dart';
import '../../providers/task_provider.dart';
import 'mail_service.dart';

/// Words that mean "look at my mail". Anchored on the nouns rather than on
/// verbs like "check", which appear in half of all sentences.
final _mailRe = RegExp(
  r'\b(inbox|e-?mails?|gmail|mail(box)?|unread|who (has )?(emailed|written)|'
  r'any(thing| mail) from)\b',
  caseSensitive: false,
);

/// A turn that is specifically about what has not been read yet.
///
/// Worth separating from the general mail question: "anything new?" wants the
/// four unread ones, and answering it with the last twelve messages including
/// eight they have already dealt with is the kind of answer that makes a
/// feature feel like it is not listening.
final _unreadRe = RegExp(
  r'\b(unread|new (e-?mails?|mail|messages?)|anything new|'
  r'not (yet )?read|haven.?t read)\b',
  caseSensitive: false,
);

bool wantsUnreadOnly(String text) => _unreadRe.hasMatch(text);

/// Words that mean "look at my day". "Schedule", "calendar", "meetings", and
/// the day words people actually use.
final _calendarRe = RegExp(
  r'\b(calendar|schedule|agenda|meetings?|appointments?|'
  r'(my|the) (day|week|morning|afternoon|evening)|what.{0,12}(on|planned)|'
  r'free time|busy)\b',
  caseSensitive: false,
);

class TurnContext {
  const TurnContext({this.mail, this.calendar});

  /// A block about the inbox, or null when the turn was not about mail.
  final String? mail;

  /// A block about the day, or null when the turn was not about the day.
  final String? calendar;

  bool get isEmpty => mail == null && calendar == null;

  /// One system note carrying whatever was gathered.
  String get promptBlock {
    final parts = <String>[
      if (mail != null) mail!,
      if (calendar != null) calendar!,
    ];
    if (parts.isEmpty) return '';
    return '${parts.join('\n\n')}\n\n'
        'This is live data, fetched because they asked. Answer from it '
        'directly. Summarise, do not list everything back at them, and never '
        'say that you are reading a data block.';
  }
}

bool wantsMail(String text) => _mailRe.hasMatch(text);
bool wantsCalendar(String text) => _calendarRe.hasMatch(text);

/// Gather whatever this turn is asking about.
///
/// Never throws and never blocks for long: each source is given its own
/// timeout, and a source that is slow or unavailable is simply absent from the
/// prompt. A coach that hangs because Gmail is down is worse than one that
/// says it could not see the inbox.
Future<TurnContext> gatherTurnContext(
  String text, {
  required TaskProvider tasks,
  required CalendarProvider calendar,
}) async {
  final needMail = wantsMail(text);
  final needCal = wantsCalendar(text);
  if (!needMail && !needCal) return const TurnContext();

  String? mailBlock;
  String? calBlock;

  await Future.wait([
    if (needMail)
      Future(() async {
        if (!MailService.instance.canRead) {
          // Two different states, and telling them apart is the difference
          // between a useful sentence and a confusing one: an account can be
          // connected for sending and still have no permission to be read.
          mailBlock = MailService.instance.isConnected
              ? 'THEIR INBOX\nThis account is connected for sending only. '
                  'Permission to read the inbox was not granted, so you cannot '
                  'see it. Say that in one line and do not guess what is in it.'
              : 'THEIR INBOX\nNo email account is connected, so you cannot '
                  'see their mail. Say so plainly and tell them they can '
                  'connect Gmail in Settings, under Connections.';
          return;
        }
        try {
          // Reading the mailbox is slow enough to need its own budget: IMAP
          // opens a TLS socket, authenticates and fetches, which is seconds
          // rather than milliseconds on a cold connection.
          final onlyUnread = wantsUnreadOnly(text);
          final msgs = await MailService.instance
              .recent(unreadOnly: onlyUnread)
              .timeout(const Duration(seconds: 40));

          if (msgs.isEmpty) {
            mailBlock = onlyUnread
                ? 'THEIR INBOX\nNothing unread. Say so in one short line, and '
                    'do not pad it out.'
                : 'THEIR INBOX\nNothing came back from their recent mail.';
          } else {
            final unread = msgs.where((m) => m.unread).length;
            mailBlock = 'THEIR INBOX (${onlyUnread ? 'unread only' : 'recent'}, '
                'newest first, $unread unread of ${msgs.length})\n'
                '${msgs.map((m) => m.promptLine).join('\n')}\n\n'
                'Lead with what actually needs them: anything asking a '
                'question, anything with a deadline, anything from a person '
                'rather than a system. Group the rest in a line. Say how many '
                'there are before you start listing, so they know the shape of '
                'it.';
          }
          debugPrint('[turn] inbox: ${msgs.length} messages '
              '(unreadOnly=$onlyUnread)');
        } catch (e) {
          debugPrint('[turn] inbox failed: $e');
          mailBlock = 'THEIR INBOX\nGmail could not be reached just now. Say '
              'so rather than guessing what is in it.';
        }
      }),
    if (needCal)
      Future(() async {
        try {
          final now = DateTime.now();
          final lines = <String>[];

          // What this app knows: the blocks they planned here.
          for (final t in tasks.todaySchedule) {
            final at = t.startTime;
            if (at == null) continue;
            final hh = at.hour.toString().padLeft(2, '0');
            final mm = at.minute.toString().padLeft(2, '0');
            lines.add('- $hh:$mm ${t.title}${t.done ? ' (done)' : ''}');
          }

          // What the phone knows: real meetings, which are the things that
          // cannot be moved and the reason a plan survives contact with the
          // day or does not.
          if (calendar.connected) {
            final events = await calendar
                .importDay(now)
                .timeout(const Duration(seconds: 12));
            for (final e in events) {
              final at = e.startTime;
              if (at == null) continue;
              final hh = at.hour.toString().padLeft(2, '0');
              final mm = at.minute.toString().padLeft(2, '0');
              lines.add('- $hh:$mm ${e.title} (from their calendar)');
            }
          }

          lines.sort();
          final nowBlock = tasks.nowBlock;
          calBlock = 'THEIR DAY (${now.day}/${now.month})\n'
              '${lines.isEmpty ? '- nothing scheduled' : lines.join('\n')}'
              '${nowBlock != null ? '\nRight now: ${nowBlock.title}' : ''}'
              '${calendar.connected ? '' : '\n(Their phone calendar is not connected, so this is only what they planned in the app.)'}';
          debugPrint('[turn] day: ${lines.length} entries');
        } catch (e) {
          debugPrint('[turn] calendar failed: $e');
          calBlock = 'THEIR DAY\nThe calendar could not be read just now.';
        }
      }),
  ]);

  return TurnContext(mail: mailBlock, calendar: calBlock);
}
