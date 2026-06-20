import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the light and dark [ThemeData] for OurMynd from the design tokens.
///
/// The custom [OmColors] palette is attached as a theme extension; standard
/// [ColorScheme]/[ThemeData] fields are filled in so that built-in Material
/// widgets also pick up the brand colors.
abstract final class AppTheme {
  static ThemeData light({bool hyperlegible = false}) =>
      _build(OmColors.light, Brightness.light, hyperlegible);

  static ThemeData dark({bool hyperlegible = false}) =>
      _build(OmColors.dark, Brightness.dark, hyperlegible);

  static ThemeData _build(OmColors c, Brightness brightness, bool hyperlegible) {
    var textTheme = AppTypography.build(c.text, c.text2);
    if (hyperlegible) textTheme = AppTypography.hyperlegibleOf(textTheme);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: Colors.white,
      primaryContainer: c.primaryTint,
      onPrimaryContainer: c.primary,
      secondary: c.accent,
      onSecondary: Colors.white,
      secondaryContainer: c.accentTint,
      onSecondaryContainer: c.accent,
      tertiary: c.flow,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.text2,
      surfaceContainerHighest: c.surfaceAlt,
      outline: c.border,
      outlineVariant: c.border,
      error: c.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      shadowColor: c.shadow,
      extensions: [c],
      dividerColor: c.border,
      iconTheme: IconThemeData(color: c.text, size: 22),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.text,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: c.bg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
    );
  }
}
