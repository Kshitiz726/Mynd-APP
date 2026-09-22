import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/email_approval.dart';
import '../../../core/services/email_intent.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../widgets/om_tappable.dart';

/// The last look before a message leaves.
///
/// Sending is the one thing the coach does that cannot be undone. A reminder
/// set wrongly is a buzz at a bad time; an email sent wrongly is in somebody
/// else's inbox forever, with the sender's name on it. So the whole message is
/// shown, not summarised: the recipient, the subject and every word of the
/// body, because approving something you were only shown the gist of is not
/// approval.
///
/// Three answers rather than two. "Never ask again" is a decision about every
/// future send, and it exists because asking somebody who has confirmed five
/// notes in a row about the sixth is not caution, it is noise. "Change
/// something" is the one that makes the whole feature usable: the draft is
/// nearly always almost right, and without it the only way to fix a word is to
/// cancel and describe the entire message again.
class EmailApprovalSheet extends StatefulWidget {
  const EmailApprovalSheet({super.key, required this.intent});

  final EmailIntent intent;

  static Future<EmailDecision?> open(
    BuildContext context,
    EmailIntent intent,
  ) =>
      showModalBottomSheet<EmailDecision>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.omColors.surface,
        // Not dismissible by accident: a swipe down that silently means "do
        // not send" would be indistinguishable from the feature hanging.
        isDismissible: false,
        enableDrag: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => EmailApprovalSheet(intent: intent),
      );

  @override
  State<EmailApprovalSheet> createState() => _EmailApprovalSheetState();
}

class _EmailApprovalSheetState extends State<EmailApprovalSheet> {
  final _change = TextEditingController();
  bool _changing = false;

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }

  void _close(EmailDecision d) {
    Haptics.light();
    Navigator.of(context).pop(d);
  }

  void _submitChange() {
    final what = _change.text.trim();
    if (what.isEmpty) return;
    _close(EmailDecision.change(what));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    final i = widget.intent;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                    AppSpacing.lg, AppSpacing.screenH, AppSpacing.md),
                child: Row(
                  children: [
                    Icon(OmIcons.byName('mail'), size: 19, color: c.primary),
                    const SizedBox(width: 10),
                    Text('Send this?',
                        style:
                            t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenH),
                  children: [
                    _Row(label: 'To', value: i.to),
                    _Row(label: 'Subject', value: i.subject),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius:
                            BorderRadius.circular(AppRadius.control),
                      ),
                      child: Text(
                        i.body,
                        style: TextStyle(
                            color: c.text, height: 1.5, fontSize: 14.5),
                      ),
                    ),
                    if (_changing) ...[
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _change,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitChange(),
                        style: TextStyle(color: c.text, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'What should be different?',
                          hintStyle:
                              TextStyle(color: c.text2.withValues(alpha: 0.75)),
                          filled: true,
                          fillColor: c.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            borderSide: BorderSide(color: c.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            borderSide: BorderSide(color: c.border),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Say it the way you would to a person. "Shorter", '
                        '"warmer", "ask about Friday too".',
                        style: TextStyle(
                            color: c.text2, fontSize: 12.5, height: 1.4),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 0,
                    AppSpacing.screenH, AppSpacing.lg),
                child: _changing
                    ? Row(
                        children: [
                          Expanded(
                            child: _Secondary(
                              label: 'Back',
                              onTap: () => setState(() => _changing = false),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 2,
                            child: _Primary(
                              label: 'Rewrite it',
                              onTap: _submitChange,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _Primary(
                            label: 'Allow',
                            onTap: () => _close(const EmailDecision.allow()),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: _Secondary(
                                  label: 'Change something',
                                  onTap: () {
                                    Haptics.light();
                                    setState(() => _changing = true);
                                  },
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _Secondary(
                                  label: 'Never ask again',
                                  onTap: () =>
                                      _close(const EmailDecision.always()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          OmTappable(
                            onTap: () =>
                                _close(const EmailDecision.cancel()),
                            feedback: OmTapFeedback.light,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              child: Text("Don't send",
                                  style: TextStyle(
                                      color: c.text2,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(label,
                style: TextStyle(
                    color: c.text2,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: c.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _Primary extends StatelessWidget {
  const _Primary({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
      ),
    );
  }
}

class _Secondary extends StatelessWidget {
  const _Secondary({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.border),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    );
  }
}
