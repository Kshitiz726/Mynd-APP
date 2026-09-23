import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/soul_service.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/om_back_button.dart';

/// SOUL.md, on its own screen, next to memory.
///
/// The app has three documents that steer the coach, and until now only two of
/// them were anywhere you could go and look at. Memory has a screen. The feed
/// instructions have a screen. This one was loaded into every conversation and
/// existed nowhere in the interface, so the only evidence it was there at all
/// was the coach sounding different, which is not evidence of anything.
///
/// Read only, deliberately. Memory is a record of you and belongs to you, so it
/// is yours to correct. This is how the coach speaks, and the half of it that
/// is not shipped with the app is written by watching how *you* write - so the
/// honest thing is to show both halves and say which is which, rather than
/// offer a text box that invites somebody to rewrite the voice of the thing
/// they are talking to.
class SoulScreen extends StatelessWidget {
  const SoulScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SoulScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final soul = SoulService.instance;
    final learned = soul.learned.trim();

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
                    child: Text('soul',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                    AppSpacing.md, AppSpacing.screenH, AppSpacing.xl),
                children: [
                  Text(
                    'Memory is what Mynd knows about you. This is how it talks '
                    'to you. It is loaded into every conversation.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: c.text2, height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // What this person's own writing has changed, first, because
                  // it is the part that is about them and the part that moves.
                  Text('what it has picked up from you',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  _Card(
                    child: Text(
                      learned.isEmpty
                          ? 'Nothing yet. Mynd adjusts how it writes by '
                              'watching how you write, and it needs a few more '
                              'messages before it changes anything.'
                          : learned,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                            color: learned.isEmpty ? c.text2 : c.text,
                          ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Text('SOUL.md', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text('the document it starts from, the same for everyone.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.sm),
                  _Card(
                    child: Text(
                      soul.base.trim().isEmpty
                          ? 'Could not be read from this build.'
                          : soul.base.trim(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.6,
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

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}
