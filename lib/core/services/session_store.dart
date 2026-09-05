import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// Persists the signed-in session so the app stays logged in across restarts
/// and a re-launch lands straight in the shell.
///
/// **Where each part lives, and why they differ.**
///
/// The tokens go in the platform keystore - Keychain on iOS, EncryptedSharedPreferences
/// on Android. They used to sit in plain SharedPreferences alongside everything
/// else, which is an XML file in the app sandbox: readable from an unencrypted
/// device backup, and readable outright on a rooted or jailbroken phone. A
/// bearer token for a health app is worth protecting properly, so it is the one
/// thing here that gets hardware-backed storage.
///
/// The display name, handle and user id stay in SharedPreferences. They are not
/// credentials, they are needed on the first frame, and secure storage is a
/// platform-channel round trip per read.
class SessionStore {
  SessionStore._();

  // Keystore entries.
  static const _kToken = 'om_session_token';
  static const _kRefresh = 'om_session_refresh';

  // Ordinary preferences.
  static const _kUserId = 'om_session_user_id';
  static const _kName = 'om_session_name';
  static const _kHandle = 'om_session_handle';

  static const _secure = FlutterSecureStorage(
    // Android: the v11 defaults are already what we want - AES-GCM for the
    // data, an RSA-OAEP key wrapped by the hardware KeyStore, and no biometric
    // prompt (the session has to be restorable during a background boot, so a
    // prompt would be unanswerable). Named explicitly rather than omitted, so a
    // future default change is a visible edit here rather than a silent one.
    aOptions: AndroidOptions(),
    // iOS: first_unlock rather than the default. The app re-arms reminders and
    // reconnects realtime on boot, before the user has unlocked the device for
    // the first time, and the stricter classes would make the token unreadable
    // in exactly that window. Not synced to iCloud.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  /// Write the current [ApiConfig] session to disk. No-op if not signed in.
  static Future<void> save() async {
    final cfg = ApiConfig.instance;
    final token = cfg.authToken;
    final userId = cfg.userId;
    if (token == null || userId == null) return;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kUserId, userId);
    await _setOrRemove(p, _kName, cfg.displayName);
    await _setOrRemove(p, _kHandle, cfg.handle);

    try {
      await _secure.write(key: _kToken, value: token);
      final refresh = cfg.refreshToken;
      if (refresh == null) {
        await _secure.delete(key: _kRefresh);
      } else {
        await _secure.write(key: _kRefresh, value: refresh);
      }
    } catch (e) {
      // A keystore that will not write is a real problem, but signing the user
      // out over it would be worse than the session simply not surviving this
      // restart. Deliberately does NOT fall back to plaintext.
      debugPrint('[session] secure write failed, session will not persist: $e');
    }
  }

  /// Restore a saved session into [ApiConfig]. Returns true if one was present.
  static Future<bool> restore() async {
    final p = await SharedPreferences.getInstance();
    final userId = p.getString(_kUserId);
    if (userId == null) return false;

    String? token;
    String? refresh;
    try {
      token = await _secure.read(key: _kToken);
      refresh = await _secure.read(key: _kRefresh);
    } catch (e) {
      debugPrint('[session] secure read failed: $e');
      return false;
    }

    // One-time migration off the old plaintext location.
    //
    // Sessions written by a build before this change are sitting in
    // SharedPreferences. Rather than signing everybody out on upgrade, move the
    // token into the keystore on first launch and delete the plaintext copy -
    // leaving it behind would keep the exact file this change exists to stop
    // using.
    if (token == null) {
      final legacy = p.getString(_kToken);
      if (legacy != null) {
        token = legacy;
        try {
          await _secure.write(key: _kToken, value: legacy);
          await p.remove(_kToken);
          debugPrint('[session] migrated token to secure storage');
        } catch (e) {
          debugPrint('[session] token migration failed: $e');
        }
      }
    }

    if (token == null) return false;

    ApiConfig.instance
      ..authToken = token
      ..refreshToken = refresh
      ..userId = userId
      ..displayName = p.getString(_kName)
      ..handle = p.getString(_kHandle);
    return true;
  }

  /// Forget the session (sign out).
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.remove(_kToken), // legacy location, in case a migration never ran
      p.remove(_kUserId),
      p.remove(_kName),
      p.remove(_kHandle),
    ]);
    try {
      await _secure.delete(key: _kToken);
      await _secure.delete(key: _kRefresh);
    } catch (e) {
      debugPrint('[session] secure clear failed: $e');
    }
  }

  static Future<void> _setOrRemove(SharedPreferences p, String key, String? value) =>
      value == null ? p.remove(key) : p.setString(key, value);
}
