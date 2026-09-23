import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/config/store_policy.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../providers/memory_provider.dart';
import '../../providers/premium_provider.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import 'memory_actions.dart';

/// Everything Mynd remembers about you, on its own screen.
///
/// The home card is a glance. This is the place you come to when you want to
/// read the whole thing, correct it, or empty out what you parked. Anything
/// that steers the coach has to be somewhere you can go and change it, not just
/// somewhere it happens to be shown.
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final memory = context.watch<MemoryProvider>();
    final m = memory.memory;
    // Editing your memory by hand is a paid feature. Free users still see and
    // read everything (and Mynd still refreshes it) - they just can't rewrite it.
    final canEdit = context.watch<PremiumProvider>().isPremium;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, AppSpacing.screenH, 8),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('memory',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (memory.refreshing)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: c.primary),
                    )
                  else ...[
                    _Action(
                      icon: 'refresh',
                      tooltip: 'Update from what I have seen',
                      onTap: () => refreshMemory(context),
                    ),
                    const SizedBox(width: 6),
                    _Action(
                      icon: 'edit',
                      tooltip: canEdit
                          ? 'Edit this yourself'
                          : 'Editing memory is a Plus feature',
                      locked: !canEdit,
                      onTap: () {
                        if (canEdit) {
                          showMemoryEditor(context);
                        } else {
                          Haptics.light();
                          Toast.show(context,
                              'Editing your memory is a Plus feature');
                          // Only where there is something to buy. Pushing this
                          // on a build that does not register the route stacks
                          // a second copy of the app instead of opening it.
                          if (StorePolicy.canSell) {
                            Navigator.of(context).pushNamed(AppRoutes.paywall);
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                    AppSpacing.md, AppSpacing.screenH, AppSpacing.xl),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.isEmpty)
                          Text(
                            memory.refreshing
                                ? 'reading everything you have told me…'
                                : "I haven't written anything about you yet. "
                                    "Tap refresh and I'll read your plans, "
                                    "goals and what you react to.",
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: c.text2, height: 1.5),
                          )
                        else
                          Text(
                            m.text,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(height: 1.55),
                          ),
                        if (m.updatedAt != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            '${m.userEdited ? 'your words' : 'written by Mynd'} · '
                            '${DateFormat.MMMd().add_jm().format(m.updatedAt!)}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: c.text2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: Text('parked thoughts',
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      Text('${memory.parked.length}',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: c.text2)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('the things you put down so you could keep going.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.md),
                  if (memory.parked.isEmpty)
                    Text('nothing parked right now.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: c.text2))
                  else
                    for (final t in memory.parked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.text,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge),
                                    const SizedBox(height: 4),
                                    Text(
                                        DateFormat.MMMd().add_jm().format(t.at),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: c.text2)),
                                  ],
                                ),
                              ),
                              OmTappable(
                                onTap: () {
                                  Haptics.light();
                                  context
                                      .read<MemoryProvider>()
                                      .removeThought(t.id);
                                },
                                feedback: OmTapFeedback.none,
                                pressedScale: 0.85,
                                child: Icon(OmIcons.byName('x'),
                                    size: 18, color: c.text2),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.icon,
      required this.onTap,
      required this.tooltip,
      this.locked = false});

  final String icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Tooltip(
      message: tooltip,
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none,
        pressedScale: 0.86,
        child: Container(
          width: 36,
          height: 36,
          decoration:
              BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(OmIcons.byName(icon), size: 16, color: c.text2),
              if (locked)
                Positioned(
                  right: -5,
                  bottom: -5,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration:
                        BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                    child: Icon(Icons.lock_rounded, size: 11, color: c.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
