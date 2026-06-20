import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

/// Applies a gentle global desaturation + brightness reduction when
/// low-stimulation mode is active, mirroring the prototype's
/// `#phone.low-stim{filter:saturate(.78) brightness(.99)}`.
///
/// Wrapping the whole app content once (in the shell) keeps the effect a single
/// concern instead of every screen reimplementing it.
class LowStimFilter extends StatelessWidget {
  const LowStimFilter({super.key, required this.child});

  final Widget child;

  // Saturation matrix at 0.78, with a tiny brightness trim (0.99).
  static const double _s = 0.78;
  static const double _b = 0.99;
  static final List<double> _matrix = () {
    const r = 0.2126, g = 0.7152, bl = 0.0722;
    final inv = (1 - _s);
    return <double>[
      (inv * r + _s) * _b, inv * g * _b, inv * bl * _b, 0, 0,
      inv * r * _b, (inv * g + _s) * _b, inv * bl * _b, 0, 0,
      inv * r * _b, inv * g * _b, (inv * bl + _s) * _b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }();

  @override
  Widget build(BuildContext context) {
    final lowStim = context.select<SettingsProvider, bool>((s) => s.lowStim);
    if (!lowStim) return child;
    return ColorFiltered(colorFilter: ColorFilter.matrix(_matrix), child: child);
  }
}
