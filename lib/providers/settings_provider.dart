import 'dart:async';

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
    unawaited(_put(_kDarkMode, _darkMode));
  }

  void toggleLowStim([bool? value]) {
    _lowStim = value ?? !_lowStim;
    notifyListeners();
    unawaited(_put(_kLowStim, _lowStim));
  }

  void toggleAutoLowStim([bool? value]) {
    _autoLowStim = value ?? !_autoLowStim;
    notifyListeners();
    unawaited(_put(_kAutoLowStim, _autoLowStim));
  }

  void toggleHyperlegible([bool? value]) {
    _hyperlegible = value ?? !_hyperlegible;
    notifyListeners();
    unawaited(_put(_kHyperlegible, _hyperlegible));
  }

  void toggleReduceMotion([bool? value]) {
    _reduceMotion = value ?? !_reduceMotion;
    notifyListeners();
    unawaited(_put(_kReduceMotion, _reduceMotion));
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
    unawaited(_put(_kHaptics, _haptics));
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

  /// Dark mode, read natively as well as from Dart.
  ///
  /// iOS reads this key directly in AppDelegate to pick the launch screen's
  /// appearance, because the launch screen is drawn by UIKit before any Dart
  /// has run. shared_preferences stores Dart keys with a `flutter.` prefix,
  /// so the native side looks up `flutter.om_dark_mode`. Renaming this breaks
  /// the launch screen silently, which is why it says so here.
  static const _kDarkMode = 'om_dark_mode';
  static const _kLowStim = 'om_low_stim';
  static const _kAutoLowStim = 'om_auto_low_stim';
  static const _kHyperlegible = 'om_hyperlegible';
  static const _kReduceMotion = 'om_reduce_motion';
  static const _kHaptics = 'om_haptics';

  /// Everything on this screen, restored.
  ///
  /// None of these were ever written down. Dark mode, low-stim, the
  /// hyperlegible font and reduce-motion all lived in memory only, so every
  /// one of them silently reset on the next launch - and reduce-motion and
  /// low-stim are accessibility settings, which makes resetting them without
  /// being asked the worst version of this bug. Only the ringtone was saved.
  ///
  /// Called before runApp so the very first frame is already in the right
  /// theme. Loading it afterwards would paint a light frame and then snap to
  /// dark, which is the flash this was meant to remove.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _darkMode = p.getBool(_kDarkMode) ?? _darkMode;
      _lowStim = p.getBool(_kLowStim) ?? _lowStim;
      _autoLowStim = p.getBool(_kAutoLowStim) ?? _autoLowStim;
      _hyperlegible = p.getBool(_kHyperlegible) ?? _hyperlegible;
      _reduceMotion = p.getBool(_kReduceMotion) ?? _reduceMotion;
      _haptics = p.getBool(_kHaptics) ?? _haptics;
      Haptics.enabled = _haptics;
      _typingSound = p.getBool(_kTypingSound) ?? _typingSound;
      _selectedRingtone = p.getString(_kRingtone) ?? _selectedRingtone;
    } catch (e) {
      // Defaults are a working app. Losing a preference is not worth
      // refusing to start over.
      debugPrint('[settings] could not restore: $e');
    }
    notifyListeners();
  }

  /// Fire and forget. A toggle must feel instant, and the write is a detail.
  Future<void> _put(String key, bool value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, value);
    } catch (e) {
      debugPrint('[settings] could not save $key: $e');
    }
  }

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
