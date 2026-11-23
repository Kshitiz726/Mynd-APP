import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/theme/app_colors.dart';

/// "Contrast sufficient in both themes" is a line in the functional test plan,
/// and it was a line somebody had to check by eye on a device. It is arithmetic,
/// so it belongs here, where it is checked on every run and in both themes at
/// once.
///
/// It found something the eye had not: light mode's secondary text sat at
/// 3.97:1 on the page, under the 4.5:1 that body text needs. Dark mode was
/// already fine throughout, which is the opposite of what everyone assumed.
double _lin(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (themeName, s) in [
    ('light', OmColors.light),
    ('dark', OmColors.dark),
  ]) {
    group('$themeName theme', () {
      final surfaces = {
        'the page': s.bg,
        'a card': s.surface,
        'a raised card': s.surfaceAlt,
      };

      test('body text is readable on every surface', () {
        // 4.5:1 is the WCAG AA floor for text below 18pt, which is all of it.
        for (final surface in surfaces.entries) {
          expect(_contrast(s.text, surface.value), greaterThanOrEqualTo(4.5),
              reason: 'primary text on ${surface.key}');
        }
      });

      test('secondary text is readable on every surface', () {
        // The one that failed. Secondary text carries dates, counts, captions
        // and most of the explanatory copy, so holding it to the same floor as
        // primary text is the point rather than a nicety.
        for (final surface in surfaces.entries) {
          expect(_contrast(s.text2, surface.value), greaterThanOrEqualTo(4.5),
              reason: 'secondary text on ${surface.key}');
        }
      });

      test('a card is distinguishable from the page behind it', () {
        // Not a WCAG rule, but a dark theme where every surface collapses into
        // one flat field is the specific thing that reads as cheap.
        expect(_contrast(s.surface, s.bg), greaterThan(1.03),
            reason: 'surface vs page');
      });

      test('a label on a filled chip is readable', () {
        // The second thing this file found, and the one that only broke in
        // dark mode: every filled chip in the app hardcoded Colors.white,
        // which is right only while the fill is dark. In dark mode these
        // fills are the light ones, so white on the selected day pill was
        // 1.18:1, on a selected length tile 2.40:1 and on the orange start
        // button 1.88:1. OmColors.onFill picks whichever of ink and white the
        // fill can actually carry, so one call is right in both themes.
        for (final entry in {
          'the accent button': s.accent,
          'a selected tile': s.brandSolid,
          'a selected day pill': s.brandSolid,
          'the brand button': s.brandSolid,
          'a success fill': s.success,
        }.entries) {
          expect(
              _contrast(OmColors.onFill(entry.value), entry.value),
              greaterThanOrEqualTo(4.5),
              reason: 'label on ${entry.key}');
        }
      });

      test('onFill picks the better of the two foregrounds', () {
        // The guarantee the call sites rely on. Checked across the ramp rather
        // than on the palette alone, so retuning a colour cannot quietly land
        // it on the wrong side of the crossover.
        for (var v = 0; v <= 255; v += 5) {
          final fill = Color.fromARGB(255, v, v, v);
          final chosen = OmColors.onFill(fill);
          final other = chosen == OmColors.ink
              ? const Color(0xFFFFFFFF)
              : OmColors.ink;
          expect(_contrast(chosen, fill),
              greaterThanOrEqualTo(_contrast(other, fill)),
              reason: 'grey $v');
        }
      });

      test('a glyph on a primary disc is visible', () {
        // A 3:1 floor, not 4.5:1: these are icons on a control, which is what
        // WCAG's non-text contrast rule covers. White on the dark theme's
        // periwinkle was 2.40:1, under even that, so the tick on a finished
        // goal and the spinner in the hero's refresh badge both faded into
        // their own discs.
        expect(_contrast(OmColors.onFill(s.primary), s.primary),
            greaterThanOrEqualTo(3.0),
            reason: 'glyph on a primary disc');
      });

      test('an inset well keeps the icon inside it visible', () {
        // The dismiss cross on a timeline block sat in a translucent white
        // disc. Over a dark card that composites to light grey, and the cross
        // - secondary text colour - measured 1.02:1 against it. The icon is a
        // non-text control, so 3:1 is its floor, but it clears the text floor
        // here either way.
        final well = _over(s.inset, s.surfaceAlt);
        expect(_contrast(s.text2, well), greaterThanOrEqualTo(4.5),
            reason: 'a cross in a well on a card');
      });

      test('a filled surface is not brighter than the text on the page', () {
        // The softness rule, written down.
        //
        // Dark mode's text sits at 15.5:1 against the page because text has
        // to. A *surface* at that luminance is a lamp, and the app had two:
        // the selected day pill was filled with c.text at 15.50:1, and the
        // accent button at 9.77:1 - on a near-black screen they were the
        // first things the eye hit and neither was the content. Both now sit
        // near secondary text, which is about where a lit control belongs.
        //
        // Only the colours used to fill a large area are held to this.
        // primary, success, error and attention are brighter, and correctly
        // so: in dark mode they are icon and label colours, where luminance
        // is legibility rather than glare.
        for (final entry in {'accent': s.accent, 'brand': s.brandSolid}.entries) {
          expect(_contrast(entry.value, s.bg), lessThanOrEqualTo(7.0),
              reason: '${entry.key} fill is brighter than the page can carry');
          // And still clearly a thing on the page, not a smudge into it.
          expect(_contrast(entry.value, s.bg), greaterThanOrEqualTo(1.6),
              reason: '${entry.key} fill has vanished into the page');
        }
      });

      test('status colours are readable as text', () {
        // All three are used as text somewhere - error in six places,
        // attention on the coach's urgent label and the sync note in Settings,
        // success on its status line - so all three get the 4.5:1 body text
        // floor rather than the 3:1 that would apply to a fill.
        //
        // An earlier version of this test exempted attention on the grounds
        // that it was fill-only. That was wrong: the search had been done one
        // line at a time and missed `color: c.attention` sitting under a
        // `copyWith(` on the line above. Hence the whole map, not a subset.
        for (final entry in {
          'success': s.success,
          'attention': s.attention,
          'error': s.error,
        }.entries) {
          expect(_contrast(entry.value, s.surface), greaterThanOrEqualTo(4.5),
              reason: '${entry.key} on a card');
        }
      });
    });
  }
}

/// [fg] painted over opaque [bg], so a translucent palette value can be
/// measured as the colour the screen actually shows.
Color _over(Color fg, Color bg) => Color.fromARGB(
      255,
      ((fg.r * fg.a + bg.r * (1 - fg.a)) * 255).round(),
      ((fg.g * fg.a + bg.g * (1 - fg.a)) * 255).round(),
      ((fg.b * fg.a + bg.b * (1 - fg.a)) * 255).round(),
    );
