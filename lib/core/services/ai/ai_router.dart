import '../groq_service.dart';
import 'ai_connections.dart';
import 'chat_backend.dart';
import 'puter_backend.dart';

/// The built-in provider: our key, our server, metered, always available.
///
/// A thin pass-through to [GroqService] on purpose. That service is untouched
/// by the multi-provider work, so the default path through the app is exactly
/// the code that was already shipping, with one indirection in front of it.
/// Nobody who never opens the provider picker gets new behaviour.
class GroqBackend implements ChatBackend {
  const GroqBackend();

  @override
  AiProvider get provider => AiProvider.groq;

  @override
  Stream<String> streamCompletion(List<Map<String, String>> messages) =>
      GroqService.instance.streamCompletion(messages);
}

/// Picks the backend a chat turn goes through.
///
/// **Only the live chat turn routes through here.** The app's other model work
/// - the feed, goals, mood, memory, soul, the brain dump - goes on calling
/// `GroqService.extract` directly against our own unmetered endpoint. Those
/// are internals tuned against that model, and quietly spending somebody's
/// personal Claude quota to re-rank their feed is not a thing they agreed to.
///
/// Falls back rather than fails. A provider that is selected but not connected
/// resolves to the built-in one, so a Puter session that has not been signed
/// in yet, or has expired, leaves a working coach instead of a dead one. The
/// chat screen separately offers to finish the connection, which is the right
/// place to ask: next to the conversation they were trying to have.
class AiRouter {
  AiRouter._();
  static final AiRouter instance = AiRouter._();

  final _groq = const GroqBackend();

  /// The provider the user chose, whether or not it can currently be used.
  AiProvider get selected => AiConnections.instance.selected;

  /// The provider that will actually answer the next turn, after fallback.
  AiProvider get effective =>
      AiConnections.instance.isConnected(selected) ? selected : AiProvider.groq;

  /// The company the next turn's data actually goes to.
  ///
  /// What the AI disclosure has to name. Reads the *effective* provider, not
  /// the selected one, because a disclosure naming a provider that fallback
  /// quietly bypassed would be worse than no disclosure at all.
  String get activeCompany => effective.company;

  ChatBackend get active => switch (effective) {
        AiProvider.groq => _groq,
        final p => PuterBackend(p),
      };

  /// Stream a chat reply through whichever provider is in play.
  Stream<String> streamCompletion(List<Map<String, String>> messages) =>
      active.streamCompletion(messages);
}
