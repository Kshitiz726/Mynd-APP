import 'package:flutter/services.dart';

/// Thin wrapper around [HapticFeedback], mirroring the prototype's `buzz()`.
///
/// Every call is gated by [enabled], which the [SettingsProvider] keeps in sync
/// with the "haptics" toggle. Calls become no-ops when disabled rather than the
/// call sites having to check.
abstract final class Haptics {
  static bool enabled = true;

  /// A light confirmation tap (e.g. completing a habit).
  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// A slightly firmer tap (task completion).
  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// A short selection tick (toggles, filters).
  static void select() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// "That did not work." A heavier single knock, distinct from [success] so a
  /// failure is felt as a failure without having to read the toast.
  static void error() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// A celebratory double pulse for finishing things.
  static Future<void> success() async {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    HapticFeedback.lightImpact();
  }
}
