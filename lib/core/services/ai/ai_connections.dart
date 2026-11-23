import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../puter_service.dart';
import 'chat_backend.dart';

/// Which provider the coach talks through, and whether it can be used yet.
///
/// There are no API keys here, and that is the point. Anthropic and Google
/// offer no way for a third-party app to run inference on somebody's consumer
/// subscription, so the only route to Claude or Gemini without asking a person
/// to paste a credential is Puter: they sign in to Puter once, Puter bills
/// them, and it proxies to the model. "Connected" therefore means exactly one
/// thing - signed in to Puter - and this class holds no secret of any kind.
///
/// The provider choice is a preference, not a secret, and the disclosure
/// screen has to read it before anything is sent, so it lives in ordinary
/// preferences.
class AiConnections extends ChangeNotifier {
  AiConnections._();
  static final AiConnections instance = AiConnections._();

  static const _kSelected = 'om_ai_provider';

  AiProvider _selected = AiProvider.groq;

  /// Which provider the coach should use. Falls back to the built-in one, so
  /// there is always something that works.
  AiProvider get selected => _selected;

  StreamSubscription<bool>? _authSub;
  bool _loaded = false;
  bool get loaded => _loaded;

  /// Whether this provider can answer right now. The built-in one always can;
  /// the Puter-routed ones need the bridge signed in.
  bool isConnected(AiProvider p) => !p.needsPuter || PuterService.instance.signedIn;

  /// True when the chosen provider cannot currently be used, which is what the
  /// chat banner and the Model screen offer to fix.
  bool get selectedNeedsConnection => !isConnected(_selected);

  /// The model id actually in play, for display. Null on the built-in one.
  String? modelFor(AiProvider p) => p.puterModel;

  /// Read the choice and start following Puter's auth state.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selected = AiProvider.fromId(prefs.getString(_kSelected));
    } catch (e) {
      debugPrint('[ai] could not read provider choice: $e');
    }

    // Puter signing in or out changes what every one of these answers, and it
    // happens outside this object (a popup, or a restored session on boot).
    // Without this the Model screen and the chat banner would keep showing a
    // stale "not connected" until something else happened to rebuild them.
    _authSub ??= PuterService.instance.authState.listen((_) => notifyListeners());

    _loaded = true;
    notifyListeners();
  }

  /// Choose which provider the coach talks through. Does not sign anybody in:
  /// a provider can be selected before Puter is connected, and the chat screen
  /// is what offers to finish the job.
  Future<void> select(AiProvider p) async {
    if (_selected == p) return;
    _selected = p;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSelected, p.id);
    } catch (e) {
      debugPrint('[ai] could not save provider choice: $e');
    }
  }

  // There is deliberately no connect() here. Signing in to Puter needs a
  // visible WebView: the popup requires a real tap inside the page that opens
  // it, and that page has to stay painted while the popup is up. A service
  // object cannot provide either, and the version of this that called
  // PuterService.signIn() on the off-screen bridge produced a sign-in screen
  // that opened blank and never finished. PuterConnectScreen owns it instead,
  // and the result arrives here through the authState subscription above.

  /// Forget the Puter session and fall back to the built-in provider, so the
  /// coach keeps working rather than pointing at something unreachable.
  Future<void> disconnect() async {
    await PuterService.instance.clearSavedSession();
    if (_selected.needsPuter) {
      await select(AiProvider.groq);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
