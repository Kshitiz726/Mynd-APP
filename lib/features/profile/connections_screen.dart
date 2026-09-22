import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/mail_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../providers/calendar_provider.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import '../schedule/widgets/calendar_connect_card.dart';

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
  bool _connecting = false;

  /// One tap, on the account they already signed in with.
  ///
  /// Typing a 16-character app password was the single worst thing in this
  /// app: it meant leaving, finding a Google settings page most people have
  /// never seen, generating a credential, and pasting it back. Almost nobody
  /// finishes that. They have already proved they own this address by signing
  /// in with it, so the only honest thing left to ask for is permission.
  Future<void> _connectGoogle() async {
    Haptics.light();
    setState(() => _connecting = true);
    final r = await MailService.instance.connectWithGoogle();
    if (!mounted) return;
    setState(() => _connecting = false);
    Toast.show(context, r.message);
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
                    busy: _connecting,
                    onConnect: _connectGoogle,
                    onDisconnect: () async {
                      final yes = await _confirmDisconnect(context);
                      if (!yes) return;
                      await mail.disconnect();
                      if (mounted) setState(() {});
                    },
                  ),
                  _Note(
                    // What it says has to match what was granted. Sending and
                    // reading are asked for separately and either can be
                    // refused, and a note that promises both while only one
                    // works is how somebody ends up believing the coach is
                    // broken when it is doing exactly what it was permitted.
                    !mail.isConnected
                        ? 'One tap, using the account you signed in with. No '
                            'password to find: you have already proved this '
                            'address is yours, so all that is left is '
                            'permission.'
                        : mail.canRead
                            ? 'Ask your coach to send something and it goes '
                                'from this address. Ask what is in your inbox '
                                'and it reads the last week and tells you. It '
                                'always shows you who it sent to.'
                            : 'Ask your coach to send something and it goes '
                                'from this address, and it always shows you '
                                'who it sent to. Reading your inbox was not '
                                'granted, so it cannot summarise your mail '
                                'yet. Reconnect to be asked again.',
                  ),
                  if (!mail.isConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: OmTappable(
                        onTap: () async {
                          await GmailConnectSheet.open(context);
                          if (mounted) setState(() {});
                        },
                        feedback: OmTapFeedback.light,
                        child: Text(
                          'Trouble connecting? Use an app password instead',
                          style: TextStyle(
                            color: c.text2,
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                            decorationColor: c.text2,
                          ),
                        ),
                      ),
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

/// Address and app password, entered once and put straight into the keychain.
class GmailConnectSheet extends StatefulWidget {
  const GmailConnectSheet({super.key});

  static Future<void> open(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.omColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const GmailConnectSheet(),
      );

  @override
  State<GmailConnectSheet> createState() => _GmailConnectSheetState();
}

class _GmailConnectSheetState extends State<GmailConnectSheet> {
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final addr = _address.text.trim();
    if (!MailService.isEmail(addr)) {
      setState(() => _error = 'That does not look like an email address.');
      return;
    }
    if (_password.text.replaceAll(RegExp(r'\s'), '').length < 12) {
      setState(() => _error =
          'An app password is 16 characters. That looks like your account '
          'password, which will not work.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    await MailService.instance.connect(
      address: addr,
      appPassword: _password.text,
      displayName: _name.text,
    );
    // Cleared the moment it is in the keychain, so it is not sitting in a
    // controller for as long as this sheet happens to stay alive.
    _password.clear();

    final r = await MailService.instance.verify();
    if (!mounted) return;

    if (!r.ok) {
      // Do not leave a credential behind that has just been proven wrong.
      await MailService.instance.disconnect();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = r.message;
      });
      return;
    }

    Navigator.of(context).pop();
    Toast.show(context, r.message);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connect Gmail',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'Use a Google app password, not your account password. It only '
              'works for sending mail, and you can revoke it on its own at any '
              'time.',
              style: TextStyle(color: c.text2, height: 1.45),
            ),
            const SizedBox(height: 10),
            OmTappable(
              onTap: () => launchUrl(
                Uri.parse('https://myaccount.google.com/apppasswords'),
                mode: LaunchMode.externalApplication,
              ),
              feedback: OmTapFeedback.light,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(OmIcons.byName('lock'), size: 15, color: c.primary),
                  const SizedBox(width: 6),
                  Text('Get an app password',
                      style: TextStyle(
                          color: c.primary,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                          decorationColor: c.primary)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _Field(
              controller: _address,
              hint: 'you@gmail.com',
              label: 'Your Gmail address',
              keyboard: TextInputType.emailAddress,
            ),
            _Field(
              controller: _name,
              hint: 'How you want to appear to people',
              label: 'From name (optional)',
            ),
            _Field(
              controller: _password,
              hint: 'abcd efgh ijkl mnop',
              label: 'App password',
              obscure: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style: TextStyle(color: c.error, height: 1.4, fontSize: 13)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(
                'The password is kept in this phone\'s keychain and is sent '
                'only to Gmail. It never reaches our servers.\n\n'
                'Saving sends one test message to yourself, so you know it '
                'works before your coach uses it.',
                style: TextStyle(color: c.text2, height: 1.45, fontSize: 13),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            OmTappable(
              onTap: _busy ? null : _save,
              enabled: !_busy,
              feedback: OmTapFeedback.none,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: _busy ? 0.4 : 1),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Connect and test',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.label,
    this.obscure = false,
    this.keyboard,
  });

  final TextEditingController controller;
  final String hint;
  final String label;
  final bool obscure;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: c.text2, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboard,
            autocorrect: false,
            enableSuggestions: !obscure,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: c.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GmailRow extends StatelessWidget {
  const _GmailRow({
    required this.connected,
    required this.address,
    required this.onConnect,
    required this.onDisconnect,
    this.busy = false,
  });

  final bool connected;
  final String? address;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final bool busy;

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
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
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
