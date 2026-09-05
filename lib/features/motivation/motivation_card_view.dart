import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../widgets/shimmer_swipe.dart';
import '../../models/motivation.dart';

/// The picture behind a day's motivation.
///
/// Searched on the web when the line was written, from what the line is about
/// (see MotivationProvider._photoQuery). That URL is stored with the line, so
/// the photograph is the one chosen for these exact words and a rewrite gets a
/// different one.
///
/// The fallback is Lorem Picsum, seeded by the words. It needs no key and no
/// account, which a decorative photograph in a shipping binary should not, and
/// seeding it means a card whose search failed still keeps one steady picture
/// rather than flickering through a new random one on every rebuild.
String motivationImageUrl(MotivationLine line,
    {int width = 900, int height = 1200}) {
  final found = line.imageUrl;
  if (found != null && found.isNotEmpty) return found;
  return 'https://picsum.photos/seed/mynd${line.imageSeed}'
      '/$width/$height?grayscale&blur=1';
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
          // Blurred here rather than at the source, because the picture now
          // comes from a real photo search and there is no url parameter to
          // ask for it. The blur is the point, not decoration: a photograph at
          // full detail competes with the sentence laid over it, which is the
          // usual way this kind of card fails.
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Image.network(
              motivationImageUrl(line),
              fit: BoxFit.cover,
              // A card with no picture yet still has to read, so the fallbacks
              // are the brand gradient rather than a broken-image glyph.
              // The photograph is a network fetch and the full-bleed card is
              // mostly photograph, so the wait is the whole screen. A sweep
              // across the brand gradient says "coming" where a blank panel
              // says "broken".
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : ShimmerSwipe(
                      child: _Fallback(colors: c.brandGradient.colors)),
              errorBuilder: (_, __, ___) =>
                  _Fallback(colors: c.brandGradient.colors),
            ),
          ),
          // The scrim is what makes the text legible over any photograph at
          // all. Without it the card is a coin toss on whichever image loads.
          //
          // Heavier through the middle than it used to be. The old values were
          // tuned against a placeholder that arrived already greyscale and
          // blurred; a real photograph is bright exactly where the sentence
          // sits, and white-on-white is what that produced.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3000000),
                  Color(0x80000000),
                  Color(0xA6000000),
                  Color(0xE6000000),
                ],
                stops: [0, 0.3, 0.62, 1],
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
  /// Never invented. A line written without any local news says so by saying
  /// less, rather than claiming a place it did not use, and a line written from
  /// their own week says that instead of naming a town it never looked at.
  static String _provenance(MotivationLine l) {
    // The person who said it outranks everything else here, and it is the one
    // fact on the card that came with the words rather than being worked out
    // about them.
    if (l.author != null && l.author!.isNotEmpty) {
      final theme = l.category?.label.toLowerCase();
      return theme == null ? l.author! : '${l.author!} . $theme';
    }
    final bits = <String>[
      if (l.category != null) l.category!.label.toLowerCase(),
      if (l.fromMemory)
        'for where you are right now'
      else if (l.place != null)
        'for your day in ${l.place}',
    ];
    // "for today" rather than a category it did not come from. A line the mood
    // chose carries no category at all, which is the honest answer.
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
