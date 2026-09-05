import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../widgets/om_tappable.dart';
import 'brain_dump_sheet.dart';
import 'goal_sheet.dart';

/// The two ways to put something new into the app, behind the (+) in the nav.
///
/// This started as a card for each on Home, then as a floating dial that could
/// be dragged around the page. Both were wrong in the same direction: an action
/// somebody takes a few times a week does not deserve a permanent surface, and
/// a button that floats over the content is a button that will eventually be
/// sitting on the thing you wanted to read. The nav bar is where the app keeps
/// the controls that are available from everywhere, so that is where this
/// belongs.
///
/// A sheet rather than icons that fly out of the bar: the bar clips its own
/// glass, so anything rising out of it would be cut off at the edge, and a
/// sheet is the same shape as every other "now tell me the details" step in the
/// app - which is what both of these open into anyway.
/// What was picked. Returned rather than acted on inside the sheet, and that
/// is the whole point of the enum existing.
///
/// The first version popped itself and then opened the next screen using its
/// OWN context - which, one line after popping, belongs to a widget that has
/// been deactivated. Everything downstream then reached back through it and
/// threw "looking up a deactivated widget's ancestor is unsafe" on the first
/// keystroke. The caller's context is still alive; it opens the next screen.
enum QuickAdd { brainDump, goal }

Future<void> showQuickAddSheet(BuildContext context) async {
  Haptics.medium();
  final choice = await showModalBottomSheet<QuickAdd>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _QuickAddSheet(),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case QuickAdd.brainDump:
      showBrainDumpSheet(context);
    case QuickAdd.goal:
      await showAddGoalSheet(context);
  }
}

class _QuickAddSheet extends StatelessWidget {
  const _QuickAddSheet();

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
          _Option(
            icon: 'sparkles',
            title: 'Brain Dump',
            blurb: 'talk or type it all out, we break it into tasks',
            onTap: () => Navigator.of(context).pop(QuickAdd.brainDump),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Option(
            icon: 'target',
            title: 'New goal',
            blurb: "something bigger, split into daily steps",
            onTap: () => Navigator.of(context).pop(QuickAdd.goal),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.primary, c.flow]),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(OmIcons.byName(icon), color: Colors.white, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          )),
                  const SizedBox(height: 2),
                  Text(blurb,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.text2,
                            height: 1.3,
                          )),
                ],
              ),
            ),
            Icon(OmIcons.byName('chevR'), size: 20, color: c.text2),
          ],
        ),
      ),
    );
  }
}
