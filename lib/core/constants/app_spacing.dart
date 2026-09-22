import 'package:flutter/widgets.dart';

/// Spacing scale used across OurMynd. ADHD-friendly layouts lean on generous,
/// *consistent* spacing, so all gaps come from this single source of truth.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  /// Horizontal padding applied to every screen body.
  static const double screenH = 18;

  /// Bottom padding so content clears the floating nav bar safely.
  static const double screenBottom = 130;

  /// Padding above the status bar / dynamic-island region.
  static const double screenTop = 16;
}

/// Corner radii. The prototype uses very round cards (28) and softer controls.
abstract final class AppRadius {
  static const double chip = 13;
  static const double control = 18;
  static const double card = 28;
  static const double sheet = 32;
  static const double pill = 999;
  static const double lg = 16;

  static const Radius chipR = Radius.circular(chip);
  static const Radius cardR = Radius.circular(card);
}

/// Common touch-target sizes (kept large for accessibility).
abstract final class AppSizes {
  static const double minTouchTarget = 48;
  static const double avatar = 40;
  /// The flat icon row. No capsule any more, so this is the glyph row itself.
  static const double navBarHeight = 58;
  static const double habitTile = 66;
}
