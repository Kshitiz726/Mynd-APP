import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// Persists the signed-in session (our JWT + the public profile) so the app
/// stays logged in across restarts and a re-launch lands straight in the shell.
///
/// The token is account-scoped (keyed by Google email on the server), so
/// restoring it brings back the user's entire account — posts, friends, chats,
/// rooms — exactly like signing back in. Cleared on sign out.
class SessionStore {
  SessionStore._();

  static const _kToken = 'om_session_token';
  static const _kUserId = 'om_session_user_id';
  static const _kName = 'om_session_name';
  static const _kHandle = 'om_session_handle';

  /// Write the current [ApiConfig] session to disk. No-op if not signed in.
  static Future<void> save() async {
    final cfg = ApiConfig.instance;
    final token = cfg.authToken;
    final userId = cfg.userId;
    if (token == null || userId == null) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kUserId, userId);
    await _setOrRemove(p, _kName, cfg.displayName);
    await _setOrRemove(p, _kHandle, cfg.handle);
  }

  /// Restore a saved session into [ApiConfig]. Returns true if one was present.
  static Future<bool> restore() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString(_kToken);
    final userId = p.getString(_kUserId);
    if (token == null || userId == null) return false;
    ApiConfig.instance
      ..authToken = token
      ..userId = userId
      ..displayName = p.getString(_kName)
      ..handle = p.getString(_kHandle);
    return true;
  }

  /// Forget the session (sign out).
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.remove(_kToken),
      p.remove(_kUserId),
      p.remove(_kName),
      p.remove(_kHandle),
    ]);
  }

  static Future<void> _setOrRemove(SharedPreferences p, String key, String? value) =>
      value == null ? p.remove(key) : p.setString(key, value);
}
