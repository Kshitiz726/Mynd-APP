import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// OurMynd typography.
///
/// - **Display / headings:** Fredoka (rounded, friendly).
/// - **Body / UI:** Lexend (tuned for reading proficiency — a deliberate
///   ADHD/dyslexia-friendly choice).
/// - **Accessibility:** when the "hyperlegible" preference is on, the entire
///   tree is rebuilt with Atkinson Hyperlegible via [hyperlegibleOf].
abstract final class AppTypography {
  static TextTheme build(Color text, Color text2) {
    // We use Inter globally to emulate the premium, classic iOS SF Pro feel.
    final display = GoogleFonts.inter;
    final body = GoogleFonts.inter;

    return TextTheme(
      // Hero / big screen titles e.g. "hey, Sam". Slightly tighter tracking on
      // the large display sizes reads more premium.
      headlineLarge:
          display(fontSize: 30, fontWeight: FontWeight.w700, color: text, height: 1.08, letterSpacing: -0.6),
      headlineMedium:
          display(fontSize: 25, fontWeight: FontWeight.w700, color: text, height: 1.1, letterSpacing: -0.4),
      headlineSmall:
          display(fontSize: 21, fontWeight: FontWeight.w700, color: text, height: 1.12, letterSpacing: -0.2),
      // Card titles, "your day".
      titleLarge: display(fontSize: 20, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.2),
      titleMedium: display(fontSize: 18, fontWeight: FontWeight.w600, color: text, letterSpacing: -0.1),
      // Section labels ("habits & routines").
      titleSmall: display(fontSize: 14, fontWeight: FontWeight.w700, color: text2),
      bodyLarge: body(fontSize: 16, fontWeight: FontWeight.w500, color: text, height: 1.5),
      bodyMedium: body(fontSize: 14, fontWeight: FontWeight.w400, color: text, height: 1.5),
      bodySmall: body(fontSize: 13, fontWeight: FontWeight.w400, color: text2, height: 1.5),
      labelLarge: display(fontSize: 16, fontWeight: FontWeight.w600, color: text, letterSpacing: 0.1),
      labelMedium: body(fontSize: 14, fontWeight: FontWeight.w600, color: text),
      // Eyebrow / overline — uppercase, wide tracking for a refined section tag.
      labelSmall: body(fontSize: 11, fontWeight: FontWeight.w700, color: text2, letterSpacing: 0.8),
    );
  }

  /// Rebuilds a text theme with Atkinson Hyperlegible while keeping sizes,
  /// weights and colors. Used by the "hyperlegible font" accessibility toggle.
  static TextTheme hyperlegibleOf(TextTheme base) {
    return GoogleFonts.atkinsonHyperlegibleTextTheme(base);
  }
}
