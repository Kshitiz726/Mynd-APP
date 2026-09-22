import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/mail_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../providers/calendar_provider.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import '../schedule/widgets/calendar_connect_card.dart';
import 'gmail_setup_flow.dart';

/// Everything this app is plugged into.
///
/// One screen rather than a control on each feature's own tab, because
/// "what has access to what" is a question people ask about the whole app at
/// once, usually when they are having second thoughts. Having to remember that
/// the calendar switch lives on Schedule is how a permission gets left on.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ConnectionsScreen()),
      );

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {

  /// Walk them through it rather than dropping a password field on them.
  ///
  /// The one-tap Google route is gone. It asked for scopes Google will not
  /// grant to an app it has not verified and annually re-assessed, so for
  /// almost everybody it failed at the consent screen and left them believing
  /// they were connected when nothing had been stored. An app password is
  /// four screens of setup and then it genuinely works, for sending and for
  /// reading, with nobody's approval needed.
  Future<void> _connectGmail() async {
    Haptics.light();
    await GmailSetupFlow.open(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final cal = context.watch<CalendarProvider>();
    final mail = MailService.instance;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  8, AppSpacing.md, AppSpacing.screenH, 0),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 4),
                  Text('Connections',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.lg,
                  AppSpacing.screenH,
                  AppSpacing.screenBottom,
                ),
                children: [
                  Text(
                    'What OurMynd can see and do on your behalf. Everything '
                    'here is off until you turn it on, and can be turned off '
                    'again from this screen.',
                    style: TextStyle(color: c.text2, height: 1.45),
                  ),

                  const _Head('calendar'),
                  const CalendarConnectCard(),
                  if (cal.connected)
                    _Note(
                      'Your coach plans around what is already in your day, '
                      'and writes the blocks you plan here into the calendar '
                      'you picked.',
                    ),

                  const _Head('gmail'),
                  _GmailRow(
                    connected: mail.isConnected,
                    address: mail.address,
                    onConnect: _connectGmail,
                    onDisconnect: () async {
                      final yes = await _confirmDisconnect(context);
                      if (!yes) return;
                      await mail.disconnect();
                      if (mounted) setState(() {});
                    },
                  ),
                  _Note(
                    mail.isConnected
                        ? 'Ask your coach to send something and it goes from '
                            'this address. Ask what is in your inbox and it '
                            'reads your recent mail and tells you. It always '
                            'shows you who it sent to, and asks before it '
                            'sends until you tell it not to.'
                        : 'Takes about a minute. You will create a password '
                            'that only works for mail, and it is kept in this '
                            "phone's keychain, never on our servers.",
                  ),

                  const _Head('coming later'),
                  const _Soon(icon: 'users', label: 'Slack'),
                  const _Soon(icon: 'file-text', label: 'Notion'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDisconnect(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Disconnect Gmail?'),
        content: const Text(
          'The app password is deleted from this phone and your coach stops '
          'being able to send mail.\n\n'
          'This does not revoke the password at Google. To do that, remove it '
          'from your Google account page.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Disconnect')),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _GmailRow extends StatelessWidget {
  const _GmailRow({
    required this.connected,
    required this.address,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool connected;
  final String? address;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: connected
                  ? c.primary.withValues(alpha: 0.12)
                  : c.surfaceAlt,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.alternate_email_rounded,
                size: 21, color: connected ? c.primary : c.text2),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(connected ? 'Connected' : 'Not connected',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                if (connected && address != null) ...[
                  const SizedBox(height: 2),
                  Text(address!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.text2, fontSize: 13)),
                ],
              ],
            ),
          ),
          OmTappable(
            onTap: () {
              Haptics.light();
              connected ? onDisconnect() : onConnect();
            },
            feedback: OmTapFeedback.none,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: connected ? c.surfaceAlt : c.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              // No busy state here any more: connecting happens in its own
              // guided screen, which owns that spinner.
              child: Text(
                      connected ? 'Disconnect' : 'Connect',
                      style: TextStyle(
                        color: connected ? c.text : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, AppSpacing.xxl, 2, AppSpacing.md),
      child: Text(
        title,
        style: TextStyle(
          color: c.text2,
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, left: 2, right: 2),
      child: Text(text,
          style: TextStyle(color: c.text2, height: 1.45, fontSize: 13)),
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon({required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(OmIcons.byName(icon), size: 18, color: c.text2),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: c.text2, fontSize: 15)),
          const Spacer(),
          Text('later',
              style: TextStyle(
                  color: c.text2, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
