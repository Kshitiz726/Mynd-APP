import 'package:flutter/foundation.dart';

/// One conversational turn, after translation.
@immutable
class PromptTurn {
  const PromptTurn(this.role, this.text);

  /// 'user' or 'assistant'. Gemini's word for the second one is 'model', which
  /// is that backend's problem to rename, not this one's.
  final String role;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PromptTurn && other.role == role && other.text == text;

  @override
  int get hashCode => Object.hash(role, text);

  @override
  String toString() => 'PromptTurn($role, ${text.length} chars)';
}

/// The prompt, split the way every provider except OpenAI wants it.
///
/// [CoachPromptBuilder] emits an OpenAI-shaped list: several `system` entries
/// (identity, the agent persona, the memory block, the context note) followed
/// by the conversation. Anthropic and Google both take a single system
/// instruction and a separate list of turns, so somebody has to do this
/// translation, and doing it wrong is how features quietly break.
///
/// Two rules carry all the risk, which is why this is pure and tested:
///
///  * **Every system message survives, in order.** The builder relies on later
///    system messages overriding earlier ones (the agent persona is written to
///    contradict the house voice, and a model reads the later instruction as
///    the winner). Dropping one, or reordering them, changes the coach's
///    personality. Joining them preserves both the content and the precedence.
///  * **Turns must alternate.** Anthropic rejects two user messages in a row.
///    The builder does not normally produce that, but a retry, an interrupted
///    stream or a trimmed history can, and a hard API error mid-conversation
///    is a worse outcome than merging two adjacent messages into one.
@immutable
class PromptParts {
  const PromptParts({required this.system, required this.turns});

  /// All system messages, joined. Empty when there were none.
  final String system;

  /// The conversation, alternating, starting with the user.
  final List<PromptTurn> turns;

  static PromptParts from(List<Map<String, String>> messages) {
    final systems = <String>[];
    final turns = <PromptTurn>[];

    for (final m in messages) {
      final role = m['role'] ?? '';
      final content = m['content'] ?? '';
      if (content.isEmpty) continue;

      if (role == 'system') {
        systems.add(content);
        continue;
      }

      // Anything that is not a system message is a turn. An unknown role is
      // treated as the user rather than dropped: losing what somebody typed
      // is the worst available outcome.
      final normalised = role == 'assistant' ? 'assistant' : 'user';

      if (turns.isNotEmpty && turns.last.role == normalised) {
        // Merge rather than send two in a row. A blank line between them keeps
        // them readable as the separate messages they were.
        final merged = '${turns.last.text}\n\n$content';
        turns[turns.length - 1] = PromptTurn(normalised, merged);
      } else {
        turns.add(PromptTurn(normalised, content));
      }
    }

    // Anthropic requires the first turn to be the user's. A leading assistant
    // turn can only come from a trimmed history that cut mid-exchange, and
    // dropping it loses less than failing the request does.
    while (turns.isNotEmpty && turns.first.role == 'assistant') {
      turns.removeAt(0);
    }

    return PromptParts(system: systems.join('\n\n'), turns: turns);
  }
}
