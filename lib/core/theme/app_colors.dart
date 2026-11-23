import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Semantic color palette for OurMynd - the **Dusk Calm** system: soft
/// periwinkle-indigo + warm peach on warm paper, tuned for a calm, premium,
/// ADHD-friendly wellness feel.
///
/// Exposed as a [ThemeExtension] so every screen reads colors via
/// `context.omColors.primary` instead of hard-coding hex values. Changing a
/// value here re-skins the entire app.
@immutable
class OmColors extends ThemeExtension<OmColors> {
  const OmColors({
    required this.primary,
    required this.primaryTint,
    required this.accent,
    required this.accentTint,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.text,
    required this.text2,
    required this.success,
    required this.attention,
    required this.error,
    required this.border,
    required this.energyHigh,
    required this.energyLow,
    required this.energyDead,
    required this.flow,
    required this.ringTrack,
    required this.gradStart,
    required this.gradEnd,
    required this.shadow,
  });

  final Color primary;
  final Color primaryTint;
  final Color accent;
  final Color accentTint;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color text;
  final Color text2;
  final Color success;
  final Color attention;
  final Color error;
  final Color border;

  /// Energy levels - the core of OurMynd's task model.
  final Color energyHigh;
  final Color energyLow;
  final Color energyDead;
  final Color flow;
  final Color ringTrack;

  /// Brand gradient stops (logo, hero surfaces, primary CTAs). [gradStart] is
  /// the lighter lilac, [gradEnd] the deeper indigo.
  final Color gradStart;
  final Color gradEnd;

  /// Tinted shadow colour (indigo-leaning in light, black in dark). Apply with
  /// `.withValues(alpha: …)` - softer and more premium than pure black.
  final Color shadow;

  /// The brand as one flat colour, for small shapes.
  ///
  /// A gradient needs room to be a gradient. On a chat bubble or a 44px button
  /// it is a few pixels of drift that reads as a rendering artefact rather than
  /// as design, and in dark mode it reads as cheap. Messaging apps use a solid
  /// fill for exactly this reason.
  ///
  /// It is the deepest stop rather than the average, because that is also the
  /// one with the most contrast under white text: 4.80:1 in light and 4.78:1
  /// in dark, against 3.19:1 and 2.40:1 for the light ends it replaces.
  Color get brandSolid => gradEnd;

  /// Near-black rather than pure black: black on a warm fill reads as a hole
  /// punched in it, this reads as ink printed on it.
  static const ink = Color(0xFF14141A);

  /// The colour that can actually be read on top of [fill].
  ///
  /// Every filled chip, pill and button in the app used to hardcode
  /// Colors.white over a palette fill. That is only right while the fill is
  /// dark, and in dark mode the palette's fills are the light ones, so one
  /// line of code inverted in every place it appeared: white on the selected
  /// day pill measured 1.18:1, on a selected length tile 2.40:1, and on the
  /// orange start button 1.88:1. The label was still being painted, it just
  /// could not be seen.
  ///
  /// Measured rather than thresholded on luminance, because the two
  /// candidates are not symmetric. Black and white tie at a luminance of
  /// 0.179, but [ink] is not black, so the crossover sits somewhere else and
  /// moves again if the palette is retuned. Comparing the two ratios is exact
  /// and stays exact.
  static Color onFill(Color fill) =>
      _contrast(ink, fill) >= _contrast(Colors.white, fill) ? ink : Colors.white;

  /// WCAG relative contrast between two opaque colours.
  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// The fill for a small well sunk into a tinted card: a round icon button,
  /// or the disc a glyph sits in.
  ///
  /// It has to flip with the theme, which a translucent white does not. White
  /// over a pale card is the soft highlight this was designed as; the same
  /// white over a dark card is a light grey blob, and the icon inside it then
  /// sat at 1.02:1. That is the dismiss cross on a timeline block: present,
  /// correctly sized, and completely invisible. In dark mode the well goes
  /// darker than the card instead, which is the direction an icon can be seen
  /// against.
  Color get inset => bg.computeLuminance() > 0.4
      ? Colors.white.withValues(alpha: 0.55)
      : Colors.black.withValues(alpha: 0.28);

  /// The signature brand gradient (top-left → bottom-right).
  ///
  /// Ramped through Oklab rather than left as two sRGB stops. Two stops band
  /// visibly once the gradient covers a large surface, and they band worst in
  /// dark mode: sRGB is gamma encoded, so a step of equal size in it is a much
  /// bigger perceptual step at the dark end, which is where a dark theme's
  /// gradients live. Oklab is perceptually uniform, so the same sweep lands in
  /// even steps and reads as one smooth wash instead of a stack of bands.
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _smoothRamp(gradStart, gradEnd),
      );

  /// Enough intermediate stops that any remaining step falls below the 1/255
  /// an 8-bit channel can represent, at the sizes a phone actually paints.
  static List<Color> _smoothRamp(Color a, Color b, {int steps = 7}) {
    final from = _Oklab.of(a);
    final to = _Oklab.of(b);
    return [
      for (var i = 0; i < steps; i++)
        _Oklab.lerp(from, to, i / (steps - 1)).toColor(),
    ];
  }

  static const light = OmColors(
    primary: Color(0xFF6B70C9),
    primaryTint: Color(0xFFE7E8F8),
    accent: Color(0xFFF0A479),
    accentTint: Color(0xFFFCEADE),
    bg: Color(0xFFF6F4F1),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFBFAF7),
    text: Color(0xFF2A2A33),
    // Darkened from #787884, which sat at 3.97:1 on the page - under the
    // 4.5:1 body text needs, and the only colour in either theme that
    // missed. Same hue (R=G, B a little higher), so nothing shifts but the
    // weight. Dark mode's text2 was already fine at 6.69:1.
    text2: Color(0xFF6B6B77),
    // Deepened so each one is readable as text, because each one is used as
    // text: error in six places, attention on the urgent label in the coach
    // and the sync note in Settings, success on its own status line. At
    // #DD7A6A an error message sat at 2.97:1, which is the least readable
    // thing in the app and the worst possible place for it.
    //
    // The hue of each is unchanged - these are the same three colours with the
    // value pulled down until they clear 4.5:1 on white - so the palette reads
    // the same, just solid enough to put words in.
    success: Color(0xFF508064),
    attention: Color(0xFFA76450),
    error: Color(0xFFAE6054),
    border: Color(0xFFEDEBE5),
    energyHigh: Color(0xFF6B70C9),
    energyLow: Color(0xFF6FB28C),
    energyDead: Color(0xFF9C9AAE),
    flow: Color(0xFF5C8AD0),
    ringTrack: Color(0xFFEAE8F1),
    gradStart: Color(0xFF8E84E6),
    gradEnd: Color(0xFF6469C6),
    shadow: Color(0xFF3A3A66),
  );

  static const dark = OmColors(
    primary: Color(0xFF9DA1EC),
    primaryTint: Color(0xFF2A2B3E),
    // Deepened from #F2AE86, which measured 9.77:1 against the page - a
    // saturated light peach filling a whole button on a near-black screen,
    // and after text the brightest thing in the theme. Nothing that is a
    // *surface* should out-shout the words on it: dark text sits at 15.5:1
    // because text has to, and a fill at 9.8:1 next to it reads as a lamp
    // rather than as a control.
    //
    // #D08E68 is the same peach with the value pulled down: 6.78:1 against
    // the page instead of 9.77, still 6.17:1 as a label on a card, and ink on
    // it is 6.77:1. Light mode is untouched - a bright fill on a pale page is
    // not glare, it is just a bright fill.
    accent: Color(0xFFD08E68),
    accentTint: Color(0xFF3A2C22),
    bg: Color(0xFF141419),
    surface: Color(0xFF1D1D26),
    surfaceAlt: Color(0xFF252530),
    text: Color(0xFFECEBF2),
    text2: Color(0xFF9B9BA8),
    success: Color(0xFF76C09A),
    attention: Color(0xFFE89A7C),
    error: Color(0xFFE5897A),
    border: Color(0xFF2D2D39),
    energyHigh: Color(0xFF9DA1EC),
    energyLow: Color(0xFF76C09A),
    energyDead: Color(0xFFA6A2C2),
    flow: Color(0xFF82A8E0),
    ringTrack: Color(0xFF2D2D39),
    // Deeper than the light pair, not lighter, and much flatter.
    //
    // Deeper because these sit under white text and the old #9DA1EC gave it
    // 2.40:1 - under the 3:1 floor even for bold text, and worse than the same
    // text in light mode.
    //
    // Flatter because a wide gradient on a dark surface is the single thing
    // that makes a dark theme look unserious. The span here is half the light
    // theme's, so a button reads as one solid colour with a little depth in it
    // rather than a sweep. White text on it is 4.78:1 and it holds 3.84:1
    // against the page, both better than the wider version managed.
    gradStart: Color(0xFF6E73D2),
    gradEnd: Color(0xFF6468CC),
    shadow: Color(0xFF000000),
  );

  @override
  OmColors copyWith({
    Color? primary,
    Color? primaryTint,
    Color? accent,
    Color? accentTint,
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? text,
    Color? text2,
    Color? success,
    Color? attention,
    Color? error,
    Color? border,
    Color? energyHigh,
    Color? energyLow,
    Color? energyDead,
    Color? flow,
    Color? ringTrack,
    Color? gradStart,
    Color? gradEnd,
    Color? shadow,
  }) {
    return OmColors(
      primary: primary ?? this.primary,
      primaryTint: primaryTint ?? this.primaryTint,
      accent: accent ?? this.accent,
      accentTint: accentTint ?? this.accentTint,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      success: success ?? this.success,
      attention: attention ?? this.attention,
      error: error ?? this.error,
      border: border ?? this.border,
      energyHigh: energyHigh ?? this.energyHigh,
      energyLow: energyLow ?? this.energyLow,
      energyDead: energyDead ?? this.energyDead,
      flow: flow ?? this.flow,
      ringTrack: ringTrack ?? this.ringTrack,
      gradStart: gradStart ?? this.gradStart,
      gradEnd: gradEnd ?? this.gradEnd,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  OmColors lerp(ThemeExtension<OmColors>? other, double t) {
    if (other is! OmColors) return this;
    return OmColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryTint: Color.lerp(primaryTint, other.primaryTint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentTint: Color.lerp(accentTint, other.accentTint, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      success: Color.lerp(success, other.success, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      error: Color.lerp(error, other.error, t)!,
      border: Color.lerp(border, other.border, t)!,
      energyHigh: Color.lerp(energyHigh, other.energyHigh, t)!,
      energyLow: Color.lerp(energyLow, other.energyLow, t)!,
      energyDead: Color.lerp(energyDead, other.energyDead, t)!,
      flow: Color.lerp(flow, other.flow, t)!,
      ringTrack: Color.lerp(ringTrack, other.ringTrack, t)!,
      gradStart: Color.lerp(gradStart, other.gradStart, t)!,
      gradEnd: Color.lerp(gradEnd, other.gradEnd, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// Oklab, just enough of it to walk between two brand colours evenly.
///
/// Only the two conversions and a lerp. Interpolating in sRGB is what puts a
/// dull, slightly grey middle in an indigo ramp and what makes the ramp band;
/// Oklab is close enough to perceptually uniform that the midpoint looks like
/// the midpoint.
@immutable
class _Oklab {
  const _Oklab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;

  static double _toLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _toSrgb(double c) => c <= 0.0031308
      ? c * 12.92
      : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

  static _Oklab of(Color c) {
    final r = _toLinear(c.r);
    final g = _toLinear(c.g);
    final bb = _toLinear(c.b);

    // Linear sRGB → LMS, then the cube root that does the perceptual work.
    final l = math.pow(
            0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bb, 1 / 3)
        .toDouble();
    final m = math.pow(
            0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bb, 1 / 3)
        .toDouble();
    final s = math.pow(
            0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bb, 1 / 3)
        .toDouble();

    return _Oklab(
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    );
  }

  static _Oklab lerp(_Oklab x, _Oklab y, double t) => _Oklab(
        x.l + (y.l - x.l) * t,
        x.a + (y.a - x.a) * t,
        x.b + (y.b - x.b) * t,
      );

  Color toColor() {
    final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
    final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
    final s_ = l - 0.0894841775 * a - 1.2914855480 * b;

    final lc = l_ * l_ * l_;
    final mc = m_ * m_ * m_;
    final sc = s_ * s_ * s_;

    // Clamped because a lerp between two in-gamut colours can still pass
    // marginally outside it, and a negative channel would wrap to bright.
    double ch(double v) => (_toSrgb(v).clamp(0.0, 1.0)) * 255.0;

    return Color.fromARGB(
      255,
      ch(4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc).round(),
      ch(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc).round(),
      ch(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc).round(),
    );
  }
}

/// Convenience accessors so widgets can write `context.omColors.primary`
/// and `context.omText` instead of the verbose extension lookups.
extension OmThemeX on BuildContext {
  OmColors get omColors => Theme.of(this).extension<OmColors>()!;
  TextTheme get omText => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
