import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/motivation_provider.dart';
import '../../../widgets/om_tappable.dart';
import '../../motivation/motivation_card_view.dart';

/// Today's line, on the way past.
///
/// The same words that arrive as a notification, kept somewhere they can be
/// read again. A notification is gone the moment it is swiped, and the line
/// somebody wanted was usually the one that arrived while they were busy.
class MotivationCard extends StatefulWidget {
  const MotivationCard({super.key});

  @override
  State<MotivationCard> createState() => _MotivationCardState();
}

class _MotivationCardState extends State<MotivationCard> {
  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) {
    final c = context.omColors;
    final m = context.watch<MotivationProvider>();
    final line = m.latest;
    final setUp = m.settings.onboarded;

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
                        motivationImageUrl(line.at, width: 300, height: 300),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                                ? child
                                : ColoredBox(color: c.surfaceAlt),
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
                                  ? (line.place == null
                                      ? 'today'
                                      : 'today, in ${line.place}')
                                  : 'daily motivation',
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
