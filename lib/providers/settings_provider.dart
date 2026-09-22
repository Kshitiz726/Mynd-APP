import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// A soft tick while the coach is composing.
  ///
  /// On by default because it was asked for, and separately switchable
  /// because a repeating sound is exactly the kind of thing that is pleasant
  /// to one person and unbearable to another, and this app's users are more
  /// likely than most to be in the second group.
  bool _typingSound = true;

  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _sleepTime = const TimeOfDay(hour: 22, minute: 0);
  String _selectedRingtone = 'Default';

  bool get darkMode => _darkMode;
  bool get lowStim => _lowStim;
  bool get autoLowStim => _autoLowStim;
  bool get hyperlegible => _hyperlegible;
  bool get reduceMotion => _reduceMotion;
  bool get haptics => _haptics;
  bool get typingSound => _typingSound;
  TimeOfDay get wakeUpTime => _wakeUpTime;
  TimeOfDay get sleepTime => _sleepTime;
  String get selectedRingtone => _selectedRingtone;

  ThemeMode get themeMode => _darkMode ? ThemeMode.dark : ThemeMode.light;

  /// How many backlog tasks to show at once. Tighter in low-stim mode to
  /// reduce overwhelm - mirrors `cap = lowStim ? 2 : 3` in the prototype.
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

  Future<void> toggleTypingSound([bool? value]) async {
    _typingSound = value ?? !_typingSound;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kTypingSound, _typingSound);
    } catch (_) {/* the setting still applies for this session */}
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

  /// Where the chosen tone is stored. NotificationService reads the same key
  /// directly, because scheduling also happens from the OS boot receiver, where
  /// there is no provider to ask.
  static const _kRingtone = 'om_selected_ringtone';
  static const _kTypingSound = 'om_typing_sound';

  /// Restore the tone. Held only in memory before, so every launch silently
  /// reset the picker to 'Default' and the choice never survived a restart.
  Future<void> loadRingtone() async {
    final p = await SharedPreferences.getInstance();
    final typing = p.getBool(_kTypingSound);
    if (typing != null) _typingSound = typing;
    final saved = p.getString(_kRingtone);
    if (saved == null || saved == _selectedRingtone) {
      if (typing != null) notifyListeners();
      return;
    }
    _selectedRingtone = saved;
    notifyListeners();
  }

  Future<void> setRingtone(String tone) async {
    _selectedRingtone = tone;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRingtone, tone);
  }
}
