import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../models/motivation.dart';

/// The picture behind a day's motivation.
///
/// Lorem Picsum, because it needs no key and no account: a key shipped in the
/// binary to fetch a decorative photograph is a key anybody can pull back out.
/// Seeded by the day rather than random, so the same line keeps the same
/// picture all day: a quote card that reshuffles its background every time it
/// is opened feels like a slot machine rather than something that was written
/// for you.
///
/// Greyscale and blurred slightly at source. A photograph competing with the
/// sentence in front of it is the usual failure of this kind of card, and the
/// text is the only part anybody is meant to read.
String motivationImageUrl(DateTime day, {int width = 900, int height = 1200}) {
  final seed = '${day.year}${day.month}${day.day}';
  return 'https://picsum.photos/seed/mynd$seed/$width/$height?grayscale&blur=1';
}

/// The full card: the picture, the line written across it, and where it came
/// from.
class MotivationCardView extends StatelessWidget {
  const MotivationCardView({super.key, required this.line});

  final MotivationLine line;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            motivationImageUrl(line.at),
            fit: BoxFit.cover,
            // A card with no picture yet still has to read, so the fallbacks
            // are the brand gradient rather than a broken-image glyph.
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _Fallback(colors: c.brandGradient.colors),
            errorBuilder: (_, __, ___) =>
                _Fallback(colors: c.brandGradient.colors),
          ),
          // The scrim is what makes the text legible over any photograph at
          // all. Without it the card is a coin toss on whichever image loads.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x40000000), Color(0xCC000000)],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl, AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: _Round(
                      icon: LucideIcons.x,
                      onTap: () {
                        Haptics.light();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                  const Spacer(),
                  Text(
                    line.text,
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1.28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Colors.white,
                      shadows: [
                        Shadow(blurRadius: 18, color: Color(0x99000000)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Container(width: 22, height: 2, color: Colors.white54),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _provenance(line),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Where the line came from, in as many words as there are facts for.
  ///
  /// Never invented: a line written without any local news says so by saying
  /// less, rather than claiming a place it did not use.
  static String _provenance(MotivationLine l) {
    final bits = <String>[
      if (l.category != null) l.category!.label.toLowerCase(),
      if (l.place != null) 'for your day in ${l.place}',
    ];
    return bits.isEmpty ? 'for today' : bits.join(' . ');
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.35),
          ),
          child: Icon(icon, size: 19, color: Colors.white),
        ),
      );
}
