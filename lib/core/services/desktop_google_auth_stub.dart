/// Default/web stub for the desktop Google OAuth loopback flow. The real
/// implementation lives in `desktop_google_auth_io.dart` and is selected via a
/// conditional import on platforms that have `dart:io` (Windows/Linux/etc.).
/// This stub is only ever pulled in on the web target, where it's never called.
Future<bool> runDesktopGoogleAuth({required String clientId}) async {
  throw UnsupportedError('Desktop Google OAuth is only available on desktop platforms.');
}
