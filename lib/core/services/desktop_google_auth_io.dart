import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

/// Real Google OAuth for desktop (Windows/Linux) via the official "installed
/// app" loopback flow with PKCE:
///
/// 1. Spin up a localhost HTTP server on a random port (the redirect target).
/// 2. Open the system browser to Google's consent screen.
/// 3. Capture the `?code=…` Google redirects back with.
/// 4. Hand the code (+ PKCE verifier + redirect) to our backend, which does the
///    token exchange with the desktop client secret and returns our session.
///
/// The client secret never lives in the app - only the desktop *client id* is
/// baked in; the exchange happens server-side.
Future<bool> runDesktopGoogleAuth({required String clientId}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    final redirectUri = 'http://localhost:${server.port}';
    final verifier = _randomVerifier();
    final challenge = _s256Challenge(verifier);

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'prompt': 'select_account',
    });

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      throw 'Could not open the browser for Google sign-in.';
    }

    // Wait for Google to redirect back to our loopback server (ignoring stray
    // requests like /favicon.ico). Times out so a closed browser doesn't hang.
    final completer = Completer<Map<String, String>>();
    final sub = server.listen((req) async {
      final params = req.uri.queryParameters;
      final done = params.containsKey('code') || params.containsKey('error');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(done ? _doneHtml : '<!doctype html><title>OurMynd</title>');
      await req.response.close();
      if (done && !completer.isCompleted) completer.complete(params);
    });

    final params = await completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => {'error': 'timeout'},
    );
    await sub.cancel();

    if (params['error'] != null) throw 'Google sign-in cancelled (${params['error']}).';
    final code = params['code'];
    if (code == null) throw 'No authorization code returned from Google.';

    // Backend exchanges the code → verifies → creates/loads the anonymous user.
    // The flag it hands back says a different account now owns this device's
    // local data, which the caller answers by restarting the app.
    return ApiClient.instance.authWithGoogleDesktop(
      code: code,
      codeVerifier: verifier,
      redirectUri: redirectUri,
    );
  } finally {
    await server.close(force: true);
  }
}

String _randomVerifier() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final r = Random.secure();
  return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
}

String _s256Challenge(String verifier) {
  final digest = sha256.convert(ascii.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

const _doneHtml = '''
<!doctype html>
<html><head><meta charset="utf-8"><title>OurMynd</title></head>
<body style="font-family:system-ui,sans-serif;text-align:center;padding-top:90px;background:#F6F4F1;color:#2A2A33">
  <h2 style="color:#6B70C9">OurMynd</h2>
  <p>You're signed in. You can close this tab and return to the app.</p>
</body></html>
''';
