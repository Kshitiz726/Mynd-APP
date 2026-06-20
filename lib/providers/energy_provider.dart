import 'package:flutter/material.dart';

import '../models/energy_level.dart';

/// Tracks the user's currently-logged energy ("vibe"). Drives the vibe pill on
/// Home and is the default lens for the backlog filter.
class EnergyProvider extends ChangeNotifier {
  EnergyLevel _current = EnergyLevel.high;

  EnergyLevel get current => _current;

  void set(EnergyLevel level) {
    if (level == _current) return;
    _current = level;
    notifyListeners();
  }
}
