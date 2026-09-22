import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/mail_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';

/// Connecting a mailbox, as a walk rather than a form.
///
/// The one-tap Google route this replaces asked for scopes Google will not
/// grant to an app it has not verified and does not annually re-assess, so for
/// almost everybody it failed at the consent screen and left them believing
/// they were connected when nothing had been stored.
///
/// An app password genuinely works, for sending and for reading, with nobody's
/// approval needed. What it costs is four screens of setup on a Google page
/// most people have never seen, and the reason people abandon that is not the
/// typing: it is not knowing where they are, how much is left, or what they
/// are handing over. So the setup is paced, each step says what it is for, and
/// the step that matters most says plainly where the credential ends up.
class GmailSetupFlow extends StatefulWidget {
  const GmailSetupFlow({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const GmailSetupFlow(),
        ),
      );

  @override
  State<GmailSetupFlow> createState() => _GmailSetupFlowState();
}

class _GmailSetupFlowState extends State<GmailSetupFlow> {
  final _page = PageController();
  int _step = 0;

  final _address = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  static const _steps = 4;

  @override
  void dispose() {
    _page.dispose();
    _address.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _go(int to) {
    if (to < 0 || to >= _steps) return;
    Haptics.light();
    setState(() => _step = to);
    _page.animateToPage(
      to,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _save() async {
    final addr = _address.text.trim();
    if (!MailService.isEmail(addr)) {
      setState(() => _error = 'That does not look like an email address.');
      return;
    }
    // An app password is 16 characters, shown in four groups of four. The
    // account password is the thing people reach for instead, and it will not
    // work, so it is worth naming rather than failing at the handshake.
    if (_password.text.replaceAll(RegExp(r'\s'), '').length < 12) {
      setState(() => _error =
          'An app password is 16 characters. That looks like your account '
          'password, which Google will refuse.');
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
    // controller for as long as this screen happens to stay alive.
    _password.clear();

    final r = await MailService.instance.verify();
    if (!mounted) return;

    if (!r.ok) {
      // Never leave a credential behind that has just been proven wrong.
      await MailService.instance.disconnect();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = r.message;
      });
      return;
    }

    Haptics.success();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  8, AppSpacing.md, AppSpacing.screenH, 0),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 4),
                  Text('Connect Gmail',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('${_step + 1} of $_steps',
                      style: TextStyle(
                          color: c.text2,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Row(
                children: [
                  for (var i = 0; i < _steps; i++) ...[
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? c.primary
                              : c.border.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                    ),
                    if (i < _steps - 1) const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _StepWhy(onOpen: _openUrl),
                  _StepTwoFactor(onOpen: _openUrl),
                  _StepPassword(onOpen: _openUrl),
                  _StepPaste(
                    address: _address,
                    name: _name,
                    password: _password,
                    error: _error,
                  ),
                ],
              ),
            ),
            _Footer(
              step: _step,
              last: _steps - 1,
              busy: _busy,
              onBack: () => _go(_step - 1),
              onNext: () => _go(_step + 1),
              onFinish: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// The buttons, which say different things on the last step.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.last,
    required this.busy,
    required this.onBack,
    required this.onNext,
    required this.onFinish,
  });

  final int step;
  final int last;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final isLast = step == last;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.md,
          AppSpacing.screenH, AppSpacing.xl),
      child: Row(
        children: [
          if (step > 0)
            OmTappable(
              onTap: busy ? null : onBack,
              enabled: !busy,
              feedback: OmTapFeedback.light,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                child: Text('Back',
                    style: TextStyle(
                        color: c.text2, fontWeight: FontWeight.w700)),
              ),
            ),
          const Spacer(),
          // Skip stays available on the middle steps: somebody who already has
          // two factor on and a password in their clipboard should not be made
          // to read three screens about it.
          if (!isLast && step > 0)
            OmTappable(
              onTap: busy ? null : onNext,
              enabled: !busy,
              feedback: OmTapFeedback.light,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                child: Text('Skip',
                    style: TextStyle(
                        color: c.text2, fontWeight: FontWeight.w700)),
              ),
            ),
          const SizedBox(width: 6),
          OmTappable(
            onTap: busy ? null : (isLast ? onFinish : onNext),
            enabled: !busy,
            feedback: OmTapFeedback.none,
            child: Container(
              height: 52,
              constraints: const BoxConstraints(minWidth: 148),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 26),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: busy ? 0.4 : 1),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isLast ? 'Connect' : 'Continue',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared shape of a step: a title, a body, and whatever it needs below.
class _Step extends StatelessWidget {
  const _Step({required this.title, required this.body, this.child});


  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.xl, AppSpacing.screenH, AppSpacing.xl),
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
        const SizedBox(height: AppSpacing.md),
        Text(body, style: TextStyle(color: c.text2, height: 1.5, fontSize: 15)),
        if (child != null) ...[
          const SizedBox(height: AppSpacing.xl),
          child!,
        ],
      ],
    );
  }
}

class _StepWhy extends StatelessWidget {
  const _StepWhy({required this.onOpen});
  final Future<void> Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    return const _Step(
      title: 'What your coach will be able to do',
      body: 'Send mail from your address when you ask it to, and read your '
          'recent inbox when you ask what is in it. Nothing else, and nothing '
          'without you asking first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Point(
            icon: 'lock',
            title: 'The password never leaves this phone',
            body: 'It goes straight into the iOS keychain, encrypted by the '
                'device. It is never sent to our servers, never written to a '
                'log, and never included in a backup we can read.',
          ),
          _Point(
            icon: 'shield',
            title: 'It only works for mail',
            body: 'An app password cannot sign in to your Google account, '
                'cannot read your files, and cannot change your settings. It '
                'does mail and nothing else.',
          ),
          _Point(
            icon: 'x',
            title: 'You can revoke it on its own',
            body: 'Delete it from your Google account page at any moment and '
                'it stops working immediately, without touching your real '
                'password or any other app.',
          ),
          _Point(
            icon: 'message',
            title: 'It asks before it sends',
            body: 'Every message is shown to you first, with the option to '
                'change it, until you tell it to stop asking.',
          ),
        ],
      ),
    );
  }
}

class _StepTwoFactor extends StatelessWidget {
  const _StepTwoFactor({required this.onOpen});
  final Future<void> Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    return _Step(
      title: 'First, 2-Step Verification',
      body: 'Google only offers app passwords on accounts that have 2-Step '
          'Verification switched on. If yours is already on, skip this step.',
      child: _LinkButton(
        label: 'Open 2-Step Verification',
        onTap: () => onOpen('https://myaccount.google.com/signinoptions/two-step-verification'),
      ),
    );
  }
}

class _StepPassword extends StatelessWidget {
  const _StepPassword({required this.onOpen});
  final Future<void> Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    return _Step(
      title: 'Create the password',
      body: 'On the page that opens, type a name you will recognise later, '
          'something like OurMynd, and press Create. Google shows you 16 '
          'characters in four groups. Copy them.\n\n'
          'That page is the only place they are ever shown, so copy them '
          'before you close it. If you lose them, delete that entry and make '
          'another one. Nothing breaks.',
      child: _LinkButton(
        label: 'Open app passwords',
        onTap: () => onOpen('https://myaccount.google.com/apppasswords'),
      ),
    );
  }
}

class _StepPaste extends StatelessWidget {
  const _StepPaste({
    required this.address,
    required this.name,
    required this.password,
    required this.error,
  });

  final TextEditingController address;
  final TextEditingController name;
  final TextEditingController password;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return _Step(
      title: 'Paste it in',
      body: 'The spaces do not matter. Connecting sends one test message to '
          'your own address, so you know it works before your coach uses it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            controller: address,
            label: 'Your Gmail address',
            hint: 'you@gmail.com',
            keyboard: TextInputType.emailAddress,
          ),
          _Field(
            controller: name,
            label: 'From name (optional)',
            hint: 'How you want to appear to people',
          ),
          _Field(
            controller: password,
            label: 'App password',
            hint: 'abcd efgh ijkl mnop',
            obscure: true,
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error!,
                style: TextStyle(color: c.error, height: 1.4, fontSize: 13)),
          ],
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(OmIcons.byName('lock'), size: 17, color: c.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Stored in this phone\'s keychain, encrypted by the '
                    'device, and read only at the moment a message is sent or '
                    'your inbox is read. It never reaches our servers.',
                    style:
                        TextStyle(color: c.text2, height: 1.45, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(OmIcons.byName(icon), size: 17, color: c.primary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.3)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        color: c.text2, height: 1.45, fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(OmIcons.byName('external-link'), size: 16, color: c.primary),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: c.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboard,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboard;
  final bool obscure;

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
                  color: c.text2,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboard,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: c.text, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: c.text2.withValues(alpha: 0.7)),
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control),
                borderSide: BorderSide(color: c.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
