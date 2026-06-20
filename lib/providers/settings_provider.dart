import 'package:flutter/material.dart';

import '../core/utils/haptics.dart';

/// Global, cross-cutting UI preferences.
///
/// These map to the toggles on the Profile screen and to several CSS-level
/// behaviors in the prototype (low-stim filter, reduce-motion, hyperlegible
/// font, dark mode, haptics). Keeping them in one provider lets any screen
/// react without prop-drilling.
class SettingsProvider extends ChangeNotifier {
  bool _darkMode = false;

  /// Low-stimulation mode: desaturates the UI, flattens shadows, and hides
  /// non-essential nudges. A first-class global state, not a buried setting.
  bool _lowStim = false;

  /// Automatically enable low-stim when the user logs "brain-dead" energy.
  bool _autoLowStim = true;

  bool _hyperlegible = false;
  bool _reduceMotion = false;
  bool _haptics = true;

  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _sleepTime = const TimeOfDay(hour: 22, minute: 0);
  String _selectedRingtone = 'Default';

  bool get darkMode => _darkMode;
  bool get lowStim => _lowStim;
  bool get autoLowStim => _autoLowStim;
  bool get hyperlegible => _hyperlegible;
  bool get reduceMotion => _reduceMotion;
  bool get haptics => _haptics;
  TimeOfDay get wakeUpTime => _wakeUpTime;
  TimeOfDay get sleepTime => _sleepTime;
  String get selectedRingtone => _selectedRingtone;

  ThemeMode get themeMode => _darkMode ? ThemeMode.dark : ThemeMode.light;

  /// How many backlog tasks to show at once. Tighter in low-stim mode to
  /// reduce overwhelm — mirrors `cap = lowStim ? 2 : 3` in the prototype.
  int get backlogCap => _lowStim ? 2 : 3;

  /// Effective animation duration, collapsed to zero under reduce-motion.
  Duration motion(Duration d) => _reduceMotion ? Duration.zero : d;

  void toggleDarkMode([bool? value]) {
    _darkMode = value ?? !_darkMode;
    notifyListeners();
  }

  void toggleLowStim([bool? value]) {
    _lowStim = value ?? !_lowStim;
    notifyListeners();
  }

  void toggleAutoLowStim([bool? value]) {
    _autoLowStim = value ?? !_autoLowStim;
    notifyListeners();
  }

  void toggleHyperlegible([bool? value]) {
    _hyperlegible = value ?? !_hyperlegible;
    notifyListeners();
  }

  void toggleReduceMotion([bool? value]) {
    _reduceMotion = value ?? !_reduceMotion;
    notifyListeners();
  }

  void toggleHaptics([bool? value]) {
    _haptics = value ?? !_haptics;
    Haptics.enabled = _haptics;
    notifyListeners();
  }

  /// Called when energy is logged; turns low-stim on automatically if the user
  /// reports being "brain-dead" and the auto setting is enabled.
  void onEnergyLogged({required bool isBrainDead}) {
    if (isBrainDead && _autoLowStim && !_lowStim) {
      _lowStim = true;
      notifyListeners();
    }
  }

  void setWakeUpTime(TimeOfDay time) {
    _wakeUpTime = time;
    notifyListeners();
  }

  void setSleepTime(TimeOfDay time) {
    _sleepTime = time;
    notifyListeners();
  }

  void setRingtone(String tone) {
    _selectedRingtone = tone;
    notifyListeners();
  }
}
