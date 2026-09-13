import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../widgets/om_tappable.dart';

/// Report and block, from wherever somebody else's content is on screen.
///
/// One sheet rather than a menu per surface, because the two actions are the
/// same everywhere and Apple checks that they exist on all of them: the feed, a
/// comment, a direct message, a room. Guideline 1.2 wants a way to report
/// objectionable content and a way to block abusive users, and an app with live
/// voice - where a stranger can talk into your ear - is held to it strictly.
///
/// Both actions are deliberately one tap and immediate. A block that needs
/// confirming twice is a block somebody abandons halfway through while the
/// person they are trying to escape is still talking.
Future<bool> showModerationSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  required String authorId,
  required String authorName,
  String? snapshot,
}) async {
  Haptics.medium();
  final messenger = ScaffoldMessenger.of(context);
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ModerationSheet(
      targetType: targetType,
      targetId: targetId,
      authorId: authorId,
      authorName: authorName,
      snapshot: snapshot,
      messenger: messenger,
    ),
  );
  return result ?? false;
}

/// The reasons, in the order a person scans them. Values match the server's
/// check constraint; labels are what someone upset actually calls the thing.
const _reasons = <({String value, String label})>[
  (value: 'harassment', label: 'Harassment or bullying'),
  (value: 'hate', label: 'Hate speech'),
  (value: 'sexual', label: 'Sexual content'),
  (value: 'violence', label: 'Violence or threats'),
  (value: 'self_harm', label: 'Self-harm or suicide'),
  (value: 'spam', label: 'Spam or a scam'),
  (value: 'other', label: 'Something else'),
];

class _ModerationSheet extends StatefulWidget {
  const _ModerationSheet({
    required this.targetType,
    required this.targetId,
    required this.authorId,
    required this.authorName,
    required this.messenger,
    this.snapshot,
  });

  final String targetType;
  final String targetId;
  final String authorId;
  final String authorName;
  final String? snapshot;
  final ScaffoldMessengerState messenger;

  @override
  State<_ModerationSheet> createState() => _ModerationSheetState();
}

class _ModerationSheetState extends State<_ModerationSheet> {
  bool _pickingReason = false;
  bool _busy = false;

  Future<void> _report(String reason) async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.reportContent(
        targetType: widget.targetType,
        targetId: widget.targetId,
        reason: reason,
        snapshot: widget.snapshot,
      );
      if (!mounted) return;
      Navigator.of(context).pop(false);
      // Says what happens next. "Reported" on its own leaves people wondering
      // whether anything was actually done.
      widget.messenger.showSnackBar(const SnackBar(
        content: Text('Thanks - a human will look at this.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, 'Could not send that report. Try again.');
    }
  }

  Future<void> _block() async {
    setState(() => _busy = true);
    try {
      await ApiClient.instance.blockUser(widget.authorId);
      if (!mounted) return;
      // true tells the caller its list is now stale.
      Navigator.of(context).pop(true);
      widget.messenger.showSnackBar(SnackBar(
        content: Text('${widget.authorName} is blocked. '
            'You will not see each other any more.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, 'Could not block them. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: c.text2.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_pickingReason) ...[
            Text("What's wrong with it?",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
            const SizedBox(height: AppSpacing.sm),
            for (final r in _reasons)
              _Row(
                icon: 'x',
                label: r.label,
                onTap: () => _report(r.value),
              ),
          ] else ...[
            _Row(
              icon: 'x',
              label: 'Report this ${_noun(widget.targetType)}',
              blurb: 'Sends it to us to look at',
              onTap: () => setState(() => _pickingReason = true),
            ),
            _Row(
              icon: 'userX',
              label: 'Block ${widget.authorName}',
              blurb: 'You stop seeing each other, and they cannot message you',
              danger: true,
              onTap: _block,
            ),
          ],
        ],
      ),
    );
  }

  static String _noun(String targetType) => switch (targetType) {
        'post' => 'post',
        'comment' => 'comment',
        'message' => 'message',
        'room' => 'room',
        _ => 'account',
      };
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.blurb,
    this.danger = false,
  });

  final String icon;
  final String label;
  final String? blurb;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final ink = danger ? c.error : c.text;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      pressedScale: 0.98,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Icon(OmIcons.byName(icon), size: 20, color: ink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ink,
                          )),
                  if (blurb != null) ...[
                    const SizedBox(height: 2),
                    Text(blurb!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: c.text2,
                              height: 1.3,
                            )),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
