/// Turning the mail watch on and off, and queueing a message for later, from
/// inside a reply.
///
/// Same mechanism as the email and reminder markers, and for the same reason:
/// the reply is streamed token by token, so anything reassembled across chunks
/// risks a half-parsed instruction doing something. A line either matches
/// completely or it does not exist.
library;

class WatchIntent {
  const WatchIntent(this.on);
  final bool on;
}

class ScheduleIntent {
  const ScheduleIntent({
    required this.to,
    required this.subject,
    required this.body,
    required this.at,
  });

  final String to;
  final String subject;
  final String body;
  final DateTime at;
}

/// `[[watch: on]]` / `[[watch: off]]`
final _watchRe =
    RegExp(r'\[\[watch:\s*(on|off)\s*\]\]', caseSensitive: false);

/// `[[later: someone@example.com | 2026-09-23T09:00 | subject | body]]`
///
/// An absolute local time rather than "in two hours", because the model has
/// the current time in its context and converting once at the point of writing
/// is far safer than storing a relative offset whose origin nobody can later
/// reconstruct.
final _laterRe = RegExp(
  r'\[\[later:\s*([^|\]\s]+@[^|\]\s]+\.[^|\]\s]+)\s*\|\s*([0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2})\s*\|([^|\]]{1,200})\|([\s\S]{1,4000}?)\]\]',
  caseSensitive: false,
);

WatchIntent? parseWatchIntent(String text) {
  final m = _watchRe.firstMatch(text);
  if (m == null) return null;
  return WatchIntent(m.group(1)!.toLowerCase() == 'on');
}

List<ScheduleIntent> parseScheduleIntents(String text) {
  final out = <ScheduleIntent>[];
  for (final m in _laterRe.allMatches(text)) {
    final at = _strictTime(m.group(2)!);
    final subject = m.group(3)!.trim();
    final body = m.group(4)!.trim();
    if (at == null || subject.isEmpty || body.isEmpty) continue;
    out.add(ScheduleIntent(
      to: m.group(1)!.trim(),
      subject: subject,
      body: body,
      at: at,
    ));
  }
  return out;
}

/// Parse a local timestamp, refusing anything that is not a real moment.
///
/// DateTime.tryParse looks stricter than it is: the constructor behind it
/// normalises out of range values, so "2026-13-45T99:99" does not fail, it
/// quietly becomes a date in 2027. That is precisely the failure that must not
/// be tolerated here, because the result is a message going out at a time
/// nobody chose. So the parsed value is checked back against the text it came
/// from, and anything that moved is refused.
DateTime? _strictTime(String raw) {
  final t = raw.trim().replaceFirst(' ', 'T');
  final at = DateTime.tryParse(t);
  if (at == null) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  final round = '${at.year}-${two(at.month)}-${two(at.day)}'
      'T${two(at.hour)}:${two(at.minute)}';
  return round == t.substring(0, round.length.clamp(0, t.length)) ? at : null;
}

/// The reply with the machinery taken out.
String stripMailControlMarkers(String text) => text
    .replaceAll(_watchRe, '')
    .replaceAll(_laterRe, '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
