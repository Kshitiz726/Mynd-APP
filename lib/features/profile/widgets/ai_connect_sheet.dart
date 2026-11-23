import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/ai/ai_connections.dart';
import '../../../core/services/ai/chat_backend.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/ai_consent_provider.dart';
import '../../../widgets/om_tappable.dart';
import '../../coach/puter_connect_screen.dart';
import '../../onboarding/ai_consent_screen.dart';

/// Connecting the account that unlocks the better models.
///
/// One button, because there is one thing to do. It is worth being plain
/// about why the account is a Puter one rather than an Anthropic or Google
/// one, since that is the obvious question and the honest answer is a point in
/// the app's favour: neither company lets a third-party app run inference on
/// somebody's consumer subscription, so the alternative was asking people to
/// generate and paste an API key. Puter is what makes "sign in once" possible.
///
/// The sheet does not block on the result. Puter's sign-in is a popup in the
/// bridge WebView, and the auth state comes back through
/// `PuterService.authState`, which [AiConnections] already follows. So the
/// sheet closes and the screen behind it updates itself when the sign-in
/// lands, rather than sitting on a spinner that has to guess when it is done.
class AiConnectSheet extends StatefulWidget {
  const AiConnectSheet({super.key, required this.provider});

  final AiProvider provider;

  static Future<bool> open(BuildContext context, AiProvider provider) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiConnectSheet(provider: provider),
    );
    return ok ?? false;
  }

  @override
  State<AiConnectSheet> createState() => _AiConnectSheetState();
}

class _AiConnectSheetState extends State<AiConnectSheet> {
  bool _busy = false;
  String? _error;

  /// True when it is agreed, either already or just now.
  ///
  /// A standing agreement is not asked for again. Declining here leaves the
  /// provider unconnected, which is the honest outcome: there is nothing to
  /// connect it for if its replies may not be fetched.
  Future<bool> _consented() async {
    final consent = AiConsentProvider.instance;
    if (consent.granted) return true;

    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        // The route's own context, so the pop closes the disclosure rather
        // than whatever the sheet's context happens to resolve to.
        builder: (routeContext) => AiConsentScreen(
          source: 'connect',
          onDecided: (granted) => Navigator.of(routeContext).pop(granted),
        ),
      ),
    );
    return agreed == true;
  }

  /// Hand over to [PuterConnectScreen] rather than calling sign-in directly.
  ///
  /// Puter's sign-in is a popup, and a popup needs a real tap inside the WebView
  /// that opens it, plus an opener that stays painted while it is up. Only a
  /// visible WebView can give it either. Calling `signIn()` on the off-screen
  /// bridge produced a blank screen that never finished.
  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    Haptics.light();
    try {
      // Ask before connecting, not after.
      //
      // Connecting is the moment the person has decided to route their coach
      // through someone else, so it is the moment the disclosure belongs: it
      // names who that someone is and what reaches them. Asking later, on the
      // first message, meant the question arrived after the decision had been
      // made and in a different part of the app. Guideline 5.1.2(i) wants
      // permission before the data moves, and this is the last point before
      // anything can.
      if (!await _consented()) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }
      if (!mounted) return;

      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const PuterConnectScreen()),
      );
      if (!mounted) return;
      // Trust the auth state over the screen's return value: the bridge
      // confirming the token is what actually makes the provider usable, and
      // backing out of a sign-in that already landed should still count.
      if (ok == true || AiConnections.instance.isConnected(widget.provider)) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _busy = false;
        _error = 'That sign in did not finish. You can try again.';
      });
    } on ChatBackendException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That did not work: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    final p = widget.provider;

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.xl),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Turn on ${p.label}', style: t.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${p.label} replies come through Puter, using your own Puter '
              'account. Sign in once and it stays connected.',
              style: t.bodyMedium?.copyWith(color: c.text2, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),

            const _Point(
              icon: LucideIcons.lock,
              text: 'No API key to create or paste. Anthropic and Google do '
                  'not let an app use your Claude or Gemini subscription '
                  'directly, so Puter is what makes a plain sign in possible.',
            ),
            const _Point(
              icon: LucideIcons.wallet,
              text: 'Usage is billed to your Puter account, not to us, and '
                  'not through the App Store.',
            ),
            const _Point(
              icon: LucideIcons.messageCircle,
              text: 'This changes the conversation only. Your feed, goals, '
                  'mood and memory keep using the built in model.',
              last: true,
            ),

            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(LucideIcons.circleAlert, size: 16, color: c.error),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: t.bodySmall?.copyWith(color: c.error, height: 1.4)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            OmTappable(
              onTap: _busy ? null : _connect,
              enabled: !_busy,
              feedback: OmTapFeedback.none,
              pressedScale: 0.97,
              child: Opacity(
                opacity: _busy ? 0.6 : 1,
                child: Container(
                  height: 54,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: c.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    _busy ? 'Opening Puter…' : 'Connect Puter',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One reason this is worth doing, or one thing it will not do. Stated before
/// the button rather than after it.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.last = false});

  final IconData icon;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: c.text2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: t.bodySmall?.copyWith(color: c.text2, height: 1.45)),
          ),
        ],
      ),
    );
  }
}
