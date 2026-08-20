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

  /// The signature brand gradient (top-left → bottom-right).
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [gradStart, gradEnd],
      );

  static const light = OmColors(
    primary: Color(0xFF6B70C9),
    primaryTint: Color(0xFFE7E8F8),
    accent: Color(0xFFF0A479),
    accentTint: Color(0xFFFCEADE),
    bg: Color(0xFFF6F4F1),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFBFAF7),
    text: Color(0xFF2A2A33),
    text2: Color(0xFF787884),
    success: Color(0xFF6FB28C),
    attention: Color(0xFFE0876B),
    error: Color(0xFFDD7A6A),
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
    accent: Color(0xFFF2AE86),
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
    gradStart: Color(0xFF9DA1EC),
    gradEnd: Color(0xFF7479D6),
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

/// Convenience accessors so widgets can write `context.omColors.primary`
/// and `context.omText` instead of the verbose extension lookups.
extension OmThemeX on BuildContext {
  OmColors get omColors => Theme.of(this).extension<OmColors>()!;
  TextTheme get omText => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
