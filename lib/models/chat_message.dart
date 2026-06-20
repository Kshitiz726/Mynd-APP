/// A single turn in the coaching conversation.
///
/// [isStreaming] is true while Groq is still emitting tokens — the provider
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

  /// Factory for the welcome message shown before any user input.
  factory ChatMessage.welcome(String userName) => ChatMessage(
        id: 'welcome',
        text: userName.isNotEmpty
            ? "hey $userName — I'm Mynd, your pocket coach. what's going on right now?"
            : "hey — I'm Mynd, your pocket coach. what's going on right now?",
        fromUser: false,
      );
}
