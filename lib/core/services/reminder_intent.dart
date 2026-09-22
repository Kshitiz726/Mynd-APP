import '../../models/reminder.dart';

/// A reminder the coach agreed to set, lifted out of what it said.
///
/// The coach cannot call code, so it writes a marker into its reply and the app
/// acts on it. The marker is stripped before the message is shown, so the user
/// sees a sentence and gets a reminder, never the machinery.
///
/// A marker rather than tool calling because the reply is streamed token by
/// token: OpenAI-style tool calls arrive in a separate channel that has to be
/// reassembled across chunks, and every one of those chunks is a chance for a
/// half-parsed call to set the wrong alarm. A line of text either matches the
/// pattern completely or it does not.
class ReminderIntent {
  const ReminderIntent({
    required this.title,
    required this.hour,
    required this.minute,
    required this.repeat,
  });

  final String title;
  final int hour;
  final int minute;
  final ReminderRepeat repeat;

  Reminder toReminder() => Reminder(
        // Stable within a second, and unique enough: two reminders set in the
        // same second from one reply would be the same request twice.
        id: 'coach-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        hour: hour,
        minute: minute,
        repeat: repeat,
      );

  @override
  String toString() =>
      'ReminderIntent($title, ${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}, ${repeat.name})';
}

/// `[[remind: 14:30 | take the washing out | once]]`
///
/// Deliberately strict. A loose pattern that also matched prose would let the
/// coach set an alarm by talking about one, which is the failure that makes a
/// feature like this untrustworthy.
final _marker = RegExp(
  r'\[\[remind:\s*(\d{1,2}):(\d{2})\s*\|([^|\]]{1,120})\|\s*(once|daily)\s*\]\]',
  caseSensitive: false,
);

/// Every reminder the text asks for, in the order written.
///
/// Out-of-range clock readings are dropped rather than clamped: 25:00 is a
/// model that has lost the thread, and silently turning it into 01:00 would set
/// an alarm for a time nobody agreed to.
List<ReminderIntent> parseReminderIntents(String text) {
  final out = <ReminderIntent>[];
  for (final m in _marker.allMatches(text)) {
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2)!);
    final title = m.group(3)!.trim();
    if (h == null || min == null) continue;
    if (h < 0 || h > 23 || min < 0 || min > 59) continue;
    if (title.isEmpty) continue;
    out.add(ReminderIntent(
      title: title,
      hour: h,
      minute: min,
      repeat: ReminderRepeat.fromName(m.group(4)!.toLowerCase()),
    ));
  }
  return out;
}

/// The reply with the markers taken out, tidied so removing one from the middle
/// of a sentence does not leave a double space or a stranded blank line.
String stripReminderMarkers(String text) => text
    .replaceAll(_marker, '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
