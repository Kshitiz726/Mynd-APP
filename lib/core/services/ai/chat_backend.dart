/// Who writes the coach's replies.
///
/// **Scope: the live chat turn only.** The app also calls a model for a pile
/// of background work - the feed, goals, mood, memory, soul, the brain dump -
/// through `GroqService.extract`, and all of that deliberately stays on Groq
/// via our own server. Those are app internals on an unmetered route, tuned
/// against that model, and spending somebody's personal quota to re-rank their
/// feed would be a surprise nobody asked for. The only thing that moves is the
/// conversation the user can see.
///
/// **Why Puter and not an API key.** Anthropic and Google have no way for a
/// third-party app to run inference on somebody's consumer subscription: there
/// is no OAuth for it, and the only sanctioned programmatic access either
/// offers is an API key. Puter exists precisely to fill that gap - the user
/// signs in to Puter once, Puter bills them, and it proxies to Claude, Gemini
/// and the rest. So "use the user's own account, no API keys" has exactly one
/// implementation, and this is it. The cost is that the account they create is
/// a Puter account rather than an Anthropic one.
library;

/// A provider the coach can talk through.
///
/// Groq is the house backend: our key, our server, metered, no sign-in. The
/// others run through the user's Puter account, which is what buys the better
/// models without anybody handling an API key.
enum AiProvider {
  groq(
    id: 'groq',
    label: 'Built in',
    subtitle: 'Fast, included, no account needed',
    company: 'Groq',
    needsPuter: false,
  ),
  claude(
    id: 'claude',
    label: 'Claude Opus',
    subtitle: 'Warmest and most considered. Best for real conversation.',
    company: 'Puter, which passes it to Anthropic',
    needsPuter: true,
    puterModel: 'anthropic/claude-opus-4-8',
  ),
  gemini(
    id: 'gemini',
    label: 'Gemini Flash',
    subtitle: 'Quick and capable, lighter on your Puter credit.',
    company: 'Puter, which passes it to Google',
    needsPuter: true,
    puterModel: 'google/gemini-3.5-flash',
  );

  const AiProvider({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.company,
    required this.needsPuter,
    this.puterModel,
  });

  /// Stable identifier, stored in preferences. Never shown.
  final String id;

  /// What the picker calls it.
  final String label;

  /// One line under the label, explaining why somebody would pick it.
  final String subtitle;

  /// Who the data actually reaches.
  ///
  /// The name the AI disclosure says out loud, because naming the recipient is
  /// what Guideline 5.1.2(i) asks for. For a Puter-routed model that is two
  /// companies, not one, and saying only "Anthropic" would quietly omit the
  /// one actually receiving the request. Hence the full phrase.
  final String company;

  /// True when this provider needs the user signed in to Puter.
  final bool needsPuter;

  /// The model id to ask Puter for. Null for the built-in provider.
  final String? puterModel;

  static AiProvider fromId(String? id) =>
      AiProvider.values.firstWhere((p) => p.id == id, orElse: () => AiProvider.groq);
}

/// Thrown when a backend cannot produce a reply. Carries a message already fit
/// to show someone, because every call site ends up putting it on screen.
class ChatBackendException implements Exception {
  ChatBackendException(this.message, {this.needsSignIn = false});

  final String message;

  /// True when the fix is signing in rather than retrying. The UI treats these
  /// differently: telling somebody to "try again" when they are simply not
  /// signed in is a loop.
  final bool needsSignIn;

  @override
  String toString() => 'ChatBackendException($message)';
}

/// One way of turning a prompt into a streamed reply.
///
/// Deliberately narrow. Everything the coach's features depend on - the email
/// and reminder markers, the agent personas, the memory - is carried in the
/// message text the prompt builder produces, not in the transport. So a
/// backend only has to send those messages and stream the text back, and every
/// one of those features keeps working whichever provider is in play.
abstract class ChatBackend {
  AiProvider get provider;

  /// Stream a reply, token by token, in the order they arrive.
  Stream<String> streamCompletion(List<Map<String, String>> messages);
}
