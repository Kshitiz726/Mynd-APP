import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/motivation_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/om_tappable.dart';
import '../../../widgets/shimmer_swipe.dart';
import '../../motivation/motivation_card_view.dart';

/// Today's line, on the way past.
///
/// The same words that arrive as a notification, kept somewhere they can be
/// read again. A notification is gone the moment it is swiped, and the line
/// somebody wanted was usually the one that arrived while they were busy.
class MotivationCard extends StatefulWidget {
  const MotivationCard({super.key, this.onlyWhenWritten = false});

  /// Take up no room at all until there is a line to show.
  ///
  /// The card's empty state is an invitation: a grey square and a line of
  /// faint text offering to set the feature up. That belongs on Home, where
  /// there is room to discover things. Above the Feed it reads as a panel that
  /// failed to load, because a reader who has not set motivation up has no way
  /// to tell the difference between "nothing written yet" and "broken", and it
  /// pushes the thing they actually opened the screen for below the fold.
  final bool onlyWhenWritten;

  @override
  State<MotivationCard> createState() => _MotivationCardState();
}

class _MotivationCardState extends State<MotivationCard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, because refresh can reach for a location and the
    // OS prompt would otherwise land on a half-built screen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final p = context.read<MotivationProvider>();
      await p.load();
      if (mounted) await p.refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app is the most reliable moment there is to have
    // something current to say: time has passed, and usually so has the day.
    // The provider decides whether anything has actually moved, so this costs
    // nothing when it has not.
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<MotivationProvider>().onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final m = context.watch<MotivationProvider>();
    final line = m.latest;
    final setUp = m.settings.onboarded;

    // A rewrite is in flight, or one is a beat away. Showing the previous line
    // while a new one is being written is the worse option: it is the sentence
    // the change was meant to replace, so the card reads as having ignored
    // what just happened, which is the exact complaint the rewriting was added
    // to fix.
    //
    // `working`, not `busy`: `busy` only covers the write itself, which starts
    // 1200ms after the mood moves and can be over in a blink when the bank
    // answers. That left the loading state technically correct and never once
    // visible.
    // Nothing written and nothing set up: on the Feed this is an empty box
    // above the reading, so it takes no space at all there.
    if (widget.onlyWhenWritten && line == null && !setUp) {
      return const SizedBox.shrink();
    }

    if (m.working && setUp) return const _LoadingCard();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: OmTappable(
        onTap: () {
          Haptics.light();
          // The picture belongs to the line, so with nothing written yet there
          // is nothing to show and the tap goes to setup instead.
          if (line == null) {
            Navigator.of(context).pushNamed(AppRoutes.motivation);
            return;
          }
          Navigator.of(context).push(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => MotivationCardView(line: line),
          ));
        },
        feedback: OmTapFeedback.none,
        pressedScale: 0.99,
        child: Container(
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.border),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: context.isDark ? 0.4 : 0.07),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // A strip of the same picture the full card opens to, so the tap
              // is obviously a way into something rather than a link to
              // somewhere unrelated.
              SizedBox(
                width: 96,
                height: 96,
                child: line == null
                    ? ColoredBox(color: c.surfaceAlt)
                    : Image.network(
                        motivationImageUrl(line, width: 300, height: 300),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : ShimmerSwipe(
                                    enabled: !context
                                        .read<SettingsProvider>()
                                        .reduceMotion,
                                    child: ColoredBox(color: c.surfaceAlt),
                                  ),
                        errorBuilder: (_, __, ___) =>
                            ColoredBox(color: c.primaryTint),
                      ),
              ),
              Expanded(
                child: Container(
                  color: c.surface,
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(LucideIcons.sparkles, size: 12, color: c.accent),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              setUp && line != null
                                  ? (line.author ?? 'today')
                                  : 'daily motivation',
                              // The name goes here rather than under the words:
                              // the card is 96px and a third line would either
                              // crowd the quotation or cost it a line of its
                              // own. Only ever a name that came with the quote,
                              // never one inferred.
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: c.text2,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        line?.text ??
                            (setUp
                                ? 'writing today\'s lines…'
                                : 'a few words a day, for where you are'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: line == null ? c.text2 : c.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card while its line is being written.
///
/// Deliberately the same 96px shape, the same border and the same image strip
/// on the left as the real card, so the swap is a fill rather than a jump. A
/// spinner in place of the card would move everything below it twice.
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final still = context.watch<SettingsProvider>().reduceMotion;
    final block = c.text2.withValues(alpha: context.isDark ? 0.22 : 0.16);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      // A white band over a white card is nothing at all, which is most of why
      // this state went unseen even on the occasions it was on screen long
      // enough to notice. The whole card sits on surfaceAlt while it loads so
      // there is something for the highlight to travel over.
      child: ShimmerSwipe(
        enabled: !still,
        strength: context.isDark ? 0.22 : 0.85,
        period: const Duration(milliseconds: 1400),
        child: Container(
          height: 96,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.border),
            color: c.surfaceAlt,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: ColoredBox(color: block),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Standing in for the "today" label and the two lines of
                      // the sentence, at the widths they actually occupy, so
                      // the shape of what is coming is already on screen.
                      _Bar(width: 54, height: 9, color: block),
                      const SizedBox(height: 10),
                      _Bar(width: double.infinity, height: 11, color: block),
                      const SizedBox(height: 7),
                      _Bar(width: 168, height: 11, color: block),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
}
