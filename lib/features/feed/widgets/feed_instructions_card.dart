import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../widgets/om_tappable.dart';

/// The editor that decides what the Feed is about.
///
/// It sits at the top of the feed rather than behind Settings because it is
/// not a setting: it is the thing the feed is generated from, and seeing it
/// directly above the posts it produced is what makes the connection obvious.
/// Edit the paragraph, save, and the next edition answers the new one.
///
/// Save is disabled until the text actually differs. Rewriting an edition
/// costs a model call, and a Save that fires on an unchanged document would
/// spend one to produce the same feed again.
class FeedInstructionsCard extends StatefulWidget {
  const FeedInstructionsCard({
    super.key,
    required this.initial,
    required this.onSave,
    required this.onCancel,
  });

  final String initial;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  @override
  State<FeedInstructionsCard> createState() => _FeedInstructionsCardState();
}

class _FeedInstructionsCardState extends State<FeedInstructionsCard> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _changed =>
      _c.text.trim() != widget.initial.trim() && _c.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.border.withValues(alpha: 0.7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl,
                    AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Feed instructions',
                        style: t.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Your feed is powered by the instructions below. Any '
                      'edits that you make to this prompt will apply to '
                      'future posts on the feed.',
                      style: t.bodyMedium
                          ?.copyWith(color: c.text2, height: 1.4),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.border.withValues(alpha: 0.7)),
              // Capped rather than free-growing: the instructions can be long,
              // and a field that pushes the Save button off the bottom of the
              // screen is a field you cannot save.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: TextField(
                    controller: _c,
                    maxLines: null,
                    expands: false,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    style: t.bodyLarge?.copyWith(height: 1.45),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText:
                          'Say what you want your feed to cover, in your own '
                          'words.',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _Button(
                label: 'Cancel',
                filled: false,
                onTap: () {
                  Haptics.light();
                  widget.onCancel();
                },
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _Button(
                label: 'Save',
                filled: true,
                enabled: _changed,
                onTap: () {
                  Haptics.success();
                  widget.onSave(_c.text.trim());
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The feed's two buttons. Save carries the app's own accent rather than the
/// reference's near-black, so the primary action reads as this app's.
class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.filled,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final on = enabled;
    return OmTappable(
      onTap: on ? onTap : null,
      enabled: on,
      feedback: OmTapFeedback.none,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? c.primary.withValues(alpha: on ? 1 : 0.28)
              : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: filled
                ? Colors.white.withValues(alpha: on ? 1 : 0.75)
                : c.text,
          ),
        ),
      ),
    );
  }
}
