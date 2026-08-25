import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the legal documents live, and the one way to open them.
///
/// These are deliberately the only string literals in the app that point at the
/// site, so a move is one edit here rather than a search across every screen
/// that happens to link to them.
abstract final class Legal {
  static const String termsUrl = 'https://ourmynd.com/terms';
  static const String privacyUrl = 'https://ourmynd.com/privacy';
  static const String copyrightUrl = 'https://ourmynd.com/copyright';

  /// Opens a legal page in an in-app browser.
  ///
  /// In-app rather than handing off to Chrome, because being thrown out of the
  /// app to read a terms page - and having to find your way back - is a good
  /// way to lose someone who was mid sign-up. Falls back to the system browser
  /// if the platform has no in-app view, and fails quietly: a dead link is not
  /// worth a red error bar over the button they were about to press.
  static Future<void> open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (ok) return;
    } catch (_) {
      // Fall through to the external attempt below.
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('could not open that link')),
        );
      }
    }
  }

  static Future<void> openTerms(BuildContext context) => open(context, termsUrl);
  static Future<void> openPrivacy(BuildContext context) =>
      open(context, privacyUrl);
  static Future<void> openCopyright(BuildContext context) =>
      open(context, copyrightUrl);
}
