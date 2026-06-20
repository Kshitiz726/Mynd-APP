import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/om_icons.dart';

/// The amount of mental energy a task or the user currently has.
///
/// This is OurMynd's primary organizing concept: instead of ranking work by
/// importance (which triggers decision fatigue), tasks are tagged by the energy
/// they require, and the backlog is filtered to match the user's current vibe.
enum EnergyLevel {
  high(label: 'high', filterLabel: 'high-energy', iconName: 'zap'),
  low(label: 'low', filterLabel: 'low-energy', iconName: 'leaf'),
  dead(label: 'brain-dead', filterLabel: 'brain-dead-easy', iconName: 'battery');

  const EnergyLevel({
    required this.label,
    required this.filterLabel,
    required this.iconName,
  });

  /// Short label used on chips / tags ("high", "low", "brain-dead").
  final String label;

  /// Phrase used in empty states ("nothing brain-dead-easy right now…").
  final String filterLabel;

  final String iconName;

  IconData get icon => OmIcons.byName(iconName);

  /// Resolves the energy color from the active theme.
  Color color(BuildContext context) {
    final c = context.omColors;
    return switch (this) {
      EnergyLevel.high => c.energyHigh,
      EnergyLevel.low => c.energyLow,
      EnergyLevel.dead => c.energyDead,
    };
  }
}
