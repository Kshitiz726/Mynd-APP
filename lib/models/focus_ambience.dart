import 'package:flutter/material.dart';

/// A focus "ambience": a colourful backdrop (and matching mood) the user picks
/// when they set up a session - or switches to mid-session - so the running
/// timer sits inside a scene rather than on a flat card.
///
/// Each scene is a distinct multi-stop gradient, chosen so switching the
/// ambience visibly recolours the whole screen. (An earlier version streamed
/// online photo slideshows; they buffered to a blank white screen on device, so
/// the scene is now a self-contained gradient - instant, offline, and never
/// blank.)
class FocusAmbience {
  const FocusAmbience({
    required this.id,
    required this.label,
    required this.icon,
    this.colors = const [],
  });

  final String id;
  final String label;

  /// OmIcons name for the selector chip.
  final String icon;

  /// The gradient stops for this scene. Empty means "no scene" - the plain
  /// screen.
  final List<Color> colors;

  bool get hasScene => colors.isNotEmpty;

  /// The full-screen wash behind the timer, or null for the plain screen.
  LinearGradient? get gradient => colors.isEmpty
      ? null
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        );
}

/// The ambiences offered on the focus setup screen and in the in-session
/// switcher. "none" leads so the plain option is the default; the rest each
/// carry a vivid, distinct palette.
const List<FocusAmbience> kFocusAmbiences = [
  FocusAmbience(id: 'none', label: 'none', icon: 'x'),
  FocusAmbience(id: 'ocean', label: 'ocean', icon: 'waves', colors: [
    Color(0xFF1A2980),
    Color(0xFF26D0CE),
  ]),
  FocusAmbience(id: 'forest', label: 'forest', icon: 'leaf', colors: [
    Color(0xFF0B4D3B),
    Color(0xFF56AB6C),
    Color(0xFF9EC94A),
  ]),
  FocusAmbience(id: 'rain', label: 'rain', icon: 'cloud-rain', colors: [
    Color(0xFF3A6073),
    Color(0xFF16222A),
  ]),
  FocusAmbience(id: 'sunset', label: 'sunset', icon: 'sun', colors: [
    Color(0xFFFF5F6D),
    Color(0xFFFFC371),
  ]),
  FocusAmbience(id: 'cafe', label: 'café', icon: 'coffee', colors: [
    Color(0xFF3E2723),
    Color(0xFF8D6E63),
    Color(0xFFD7A86E),
  ]),
  FocusAmbience(id: 'twilight', label: 'twilight', icon: 'moon', colors: [
    Color(0xFF654EA3),
    Color(0xFF2C1A4D),
  ]),
];

FocusAmbience ambienceById(String? id) => kFocusAmbiences.firstWhere(
      (a) => a.id == id,
      orElse: () => kFocusAmbiences.first,
    );
