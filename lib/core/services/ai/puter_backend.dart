import '../puter_service.dart';
import 'chat_backend.dart';
import 'prompt_parts.dart';

/// The coach, talking through the user's own Puter account.
///
/// A thin adapter, and thin on purpose: [PuterService] already owns the
/// WebView bridge, the sign-in, the session restore and the streaming. The
/// only things added here are which model to ask for, and the shape of the
/// prompt.
///
/// Nothing about the coach's features lives here either. The reminder and
/// email markers, the agent personas and the memory are text produced by
/// CoachPromptBuilder, so they cross providers untouched.
class PuterBackend implements ChatBackend {
  const PuterBackend(this.provider);

  @override
  final AiProvider provider;

  @override
  Stream<String> streamCompletion(List<Map<String, String>> messages) {
    final puter = PuterService.instance;
    if (!puter.signedIn) {
      // Said as the thing the user can act on. The bridge would otherwise
      // time out after forty seconds and report that instead, which reads as
      // the app being broken rather than as "you are not signed in".
      return Stream<String>.error(ChatBackendException(
        'Connect your Puter account to use ${provider.label}.',
        needsSignIn: true,
      ));
    }
    return puter
        .streamCompletion(_normalised(messages), model: provider.puterModel)
        .handleError((Object e) => throw ChatBackendException(_say(e)));
  }

  /// Puter's own words, because they are the ones the user can act on.
  ///
  /// A PuterException is not a ChatBackendException, so it used to fall past
  /// the coach's provider-error branch into the generic "that didn't go
  /// through". The actual message was "Your account doesn't have enough
  /// credits left for this request" - which says exactly what to do - and the
  /// user never saw it. The symptom was a connected provider whose chat simply
  /// did nothing, with no stated reason.
  String _say(Object e) {
    final text = e is PuterException ? e.message : e.toString();

    // The one case worth rewording, because Puter's version points at a
    // billing page without mentioning that the app still works without it.
    if (text.toLowerCase().contains('credit')) {
      return 'Your Puter account is out of credits, so ${provider.label} '
          'cannot reply. Top up at puter.com, or switch to the built in model '
          'in Settings, which is included and needs no account.';
    }
    return text;
  }

  /// One leading system message, then strictly alternating turns.
  ///
  /// This is the fix for "Claude and Gemini are connected but the chat does
  /// nothing". CoachPromptBuilder emits an OpenAI-shaped list, and when the
  /// turn touches mail or the calendar CoachProvider inserts a *second* system
  /// message immediately before the user's line. Groq is OpenAI-compatible and
  /// takes that happily. Anthropic has no system role in the messages array at
  /// all, and Gemini has none in `contents`, so for those two the turn was
  /// rejected and the reply never arrived.
  ///
  /// [PromptParts] joins the system messages in order, so the agent persona
  /// still overrides the house voice, and merges any two same-role turns in a
  /// row, which Anthropic also refuses. Sending the result as a single leading
  /// system message keeps it valid for every provider, including the one that
  /// was already working.
  static List<Map<String, String>> _normalised(
      List<Map<String, String>> messages) {
    final parts = PromptParts.from(messages);
    return [
      if (parts.system.isNotEmpty) {'role': 'system', 'content': parts.system},
      for (final t in parts.turns) {'role': t.role, 'content': t.text},
    ];
  }
}
