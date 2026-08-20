/// A single turn in the coaching conversation.
///
/// [isStreaming] is true while Groq is still emitting tokens - the provider
/// accumulates chunks into [text] and then flips it to false. The UI uses
/// this flag to show/hide the typing indicator and to decide whether to
/// animate the cursor.
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.fromUser,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  String text;
  final bool fromUser;
  final DateTime timestamp;
  bool isStreaming;

  /// The role string expected by the Groq/OpenAI wire format.
  String get groqRole => fromUser ? 'user' : 'assistant';

  Map<String, String> toGroqMessage() => {
        'role': groqRole,
        'content': text,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'fromUser': fromUser,
        'at': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        fromUser: j['fromUser'] as bool? ?? false,
        timestamp: DateTime.tryParse(j['at'] as String? ?? ''),
      );

  /// The opening line, shown before any user input.
  ///
  /// With no name it stays nameless rather than guessing one. Inventing a name
  /// for someone is worse than not using one.
  factory ChatMessage.welcome(String userName) => ChatMessage(
        id: 'welcome',
        text: userName.trim().isNotEmpty
            ? "hey ${userName.trim()}. i'm Mynd. what's going on right now?"
            : "hey. i'm Mynd, your pocket coach. what's going on right now?",
        fromUser: false,
      );
}
