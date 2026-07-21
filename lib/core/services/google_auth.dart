import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// The one [GoogleSignIn] the app uses.
///
/// It has to be a single instance, because signing in and signing out have to
/// talk about the same thing. When the login screen owned it privately, signing
/// out of OurMynd cleared our session but left the Google grant in place, so
/// the next silent attempt would walk straight back into the account somebody
/// had just deliberately left.
class GoogleAuth {
  GoogleAuth._();

  /// Compiled in, so a build made without the --dart-define has an empty one
  /// and can never obtain an ID token. Public because that is a failure the
  /// login screen has to be able to name.
  static const serverClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static const _serverClientId = serverClientId;

  static final GoogleSignIn instance = (!kIsWeb && _serverClientId.isNotEmpty)
      ? GoogleSignIn(
          scopes: const ['email', 'profile'], serverClientId: _serverClientId)
      : GoogleSignIn(scopes: const ['email', 'profile']);

  static bool get supported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Whoever this device has already authorised us for, without showing
  /// anything. Null means we have to ask.
  static Future<GoogleSignInAccount?> silent() async {
    if (!supported) return null;
    try {
      return await instance.signInSilently();
    } catch (e) {
      debugPrint('[google] silent sign-in failed: $e');
      return null;
    }
  }

  /// Drop the Google grant as well as our session, so signing out means signing
  /// out. Failing here is not worth blocking on: the app session is already
  /// gone by the time this runs.
  static Future<void> forget() async {
    if (!supported) return;
    try {
      await instance.signOut();
    } catch (e) {
      debugPrint('[google] sign-out failed: $e');
    }
  }
}
