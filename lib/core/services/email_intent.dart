/// An email the coach agreed to send, lifted out of what it said.
///
/// Same mechanism as [ReminderIntent] in reminder_intent.dart, and for the same
/// reason: the reply is streamed token by token, and a tool call reassembled
/// across chunks is a chance for a half-parsed call to do the wrong thing. A
/// line of text either matches the pattern completely or it does not.
///
/// The stakes are higher here than for a reminder. A mis-fired reminder is a
/// buzz at the wrong time; a mis-fired email is a message in somebody else's
/// inbox that cannot be taken back. So this pattern is stricter still: the
/// recipient has to look like an address, and prose that merely discusses
/// sending mail can never match.
library;

class EmailIntent {
  const EmailIntent({
    required this.to,
    required this.subject,
    required this.body,
  });

  final String to;
  final String subject;
  final String body;

  @override
  String toString() => 'EmailIntent($to, "$subject")';
}

/// `[[email: someone@example.com | subject | body]]`
///
/// The body is last and takes everything up to the closing brackets, so it can
/// contain pipes and newlines without the pattern having to guess where it
/// ends.
final _marker = RegExp(
  r'\[\[email:\s*([^|\]\s]+@[^|\]\s]+\.[^|\]\s]+)\s*\|([^|\]]{1,200})\|([\s\S]{1,4000}?)\]\]',
  caseSensitive: false,
);

/// Every email the text asks for, in the order written.
///
/// A row with an empty subject or an empty body is dropped rather than sent
/// with a placeholder: a blank email going out under somebody's own name is
/// worse than no email at all.
List<EmailIntent> parseEmailIntents(String text) {
  final out = <EmailIntent>[];
  for (final m in _marker.allMatches(text)) {
    final to = m.group(1)!.trim();
    final subject = m.group(2)!.trim();
    final body = m.group(3)!.trim();
    if (subject.isEmpty || body.isEmpty) continue;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(to)) continue;
    out.add(EmailIntent(to: to, subject: subject, body: body));
  }
  return out;
}

/// The reply with the markers taken out, tidied so removing one from the middle
/// of a sentence does not leave a double space or a stranded blank line.
String stripEmailMarkers(String text) => text
    .replaceAll(_marker, '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
