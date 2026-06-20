import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import '../core/utils/om_icons.dart';
import 'om_tappable.dart';

/// The single, standardized back affordance used across the app — a soft,
/// circular, iOS-style chevron that always sits in the top-left.
///
/// Drop it into an [AppBar.leading], a [Row], or a [Stack] (top-left). When
/// [onTap] is omitted it pops the current route; pass [onTap] for screens that
/// need custom dismiss logic (e.g. leaving a focus room, closing an overlay).
class OmBackButton extends StatelessWidget {
  const OmBackButton({super.key, this.onTap, this.tooltip});

  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // When used as a shared header element (no custom onTap) on a screen that
    // isn't a pushed route, there's nothing to go back to — render nothing so
    // the same header works as a tab and as a pushed screen.
    if (onTap == null && !Navigator.of(context).canPop()) {
      return const SizedBox.shrink();
    }
    final button = OmTappable(
      pressedScale: 0.9,
      onTap: () {
        Haptics.light();
        if (onTap != null) {
          onTap!();
        } else {
          Navigator.of(context).maybePop();
        }
      },
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.4 : 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(OmIcons.byName('chevL'), size: 22, color: c.text),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
