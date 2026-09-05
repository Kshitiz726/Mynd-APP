import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/health_consent_provider.dart';
import 'api_client.dart';
import 'api_config.dart';

/// Keeps a client-owned document (the backlog, goals, habits…) with the
/// account instead of the phone it was typed into.
///
/// The app's state has always been local: fast, works on a plane, and
/// completely lost the moment you sign in somewhere else. This mirrors each
/// document to the server after it changes and reads it back at launch, so
/// installing on a second device brings your backlog with you.
///
/// Local storage stays the source of truth for reads. Nothing here is on the
/// path between a tap and the screen updating: a failed or slow sync costs you
/// nothing in the moment, which is the only way an offline-capable app can
/// treat a network it does not control.
///
/// Conflicts are last-write-wins on a timestamp. Honest for a document one
/// person edits from one place at a time, and it does not invent a merge that
/// would silently produce a day nobody planned.
class StateSync {
  StateSync._();

  /// When this device last wrote [key], as epoch ms. Compared against the
  /// server's own stamp to decide which copy is the newer one.
  static String _localStampKey(String key) => 'om_sync_at_$key';

  static final Map<String, Timer> _debounce = {};
  static final Map<String, Object> _pending = {};

  static bool get _signedIn => ApiConfig.instance.authToken != null;

  /// The documents that carry health-related information, and so may only
  /// leave the device with consent. Mirrors HEALTH_STATE_KEYS in
  /// server/src/routes/consent.ts - the server refuses these writes outright,
  /// and this is here so the app does not spend the round trip finding out.
  ///
  /// Only these two. The backlog, goals, habits and the rest sync regardless,
  /// because withdrawing consent is promised not to cost access to the app.
  static const _healthKeys = {'mood', 'memory'};

  /// May [key] be mirrored to the account right now?
  static bool _mayPush(String key) =>
      !_healthKeys.contains(key) || HealthConsentProvider.instance.granted;

  /// The newest copy of [key], or null to keep whatever is local.
  ///
  /// Returns null when this device's copy is the newer one, when the account
  /// has nothing parked, or when the server cannot be reached. All three mean
  /// the same thing to the caller: carry on with what you have.
  static Future<Object?> newerRemote(String key) async {
    if (!_signedIn) return null;
    try {
      final remote = await ApiClient.instance.fetchState(key);
      if (remote.value == null) {
        // Nothing on the server yet. Push what this device has so the account
        // is seeded rather than staying empty until the next edit.
        return null;
      }
      final p = await SharedPreferences.getInstance();
      final localAt = p.getInt(_localStampKey(key)) ?? 0;
      final remoteAt = remote.updatedAt?.millisecondsSinceEpoch ?? 0;
      if (remoteAt <= localAt) return null;

      debugPrint('[sync] $key: taking the server copy '
          '(remote=$remoteAt > local=$localAt)');
      return remote.value;
    } catch (e) {
      debugPrint('[sync] $key: could not read the server copy: $e');
      return null;
    }
  }

  /// Mirror [value] up. Debounced, because the callers already debounce their
  /// own disk writes at 400ms and a drag gesture should not be a hundred
  /// requests.
  static void push(String key, Object value) {
    if (!_signedIn) return;
    // Without consent a health document stays on the phone. Dropped rather
    // than queued: holding it to send later would be keeping health data
    // pending upload from someone who declined, which is the thing being
    // avoided, only less visibly.
    if (!_mayPush(key)) {
      _pending.remove(key);
      _debounce.remove(key)?.cancel();
      return;
    }
    _pending[key] = value;
    _debounce[key]?.cancel();
    _debounce[key] = Timer(const Duration(seconds: 3), () => _flush(key));
  }

  /// Send everything waiting right now. Called when the app is going away, so
  /// the last edit before you close it is not the one that gets lost.
  static Future<void> flushAll() async {
    final keys = _pending.keys.toList();
    for (final k in keys) {
      _debounce[k]?.cancel();
      await _flush(k);
    }
  }

  static Future<void> _flush(String key) async {
    final value = _pending.remove(key);
    _debounce.remove(key);
    if (value == null || !_signedIn) return;
    // Re-checked here as well as in push(): consent can be withdrawn during
    // the three seconds a write sits in the debounce, and the last thing a
    // withdrawal should do is let one more upload through behind it.
    if (!_mayPush(key)) return;
    try {
      await ApiClient.instance.putState(key, value);
      final p = await SharedPreferences.getInstance();
      // Stamped with our own clock, matching what we compare on the way back
      // in. The server's clock would be better, but comparing two clocks is
      // worse than comparing one to itself.
      await p.setInt(_localStampKey(key), DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      // Left un-stamped on purpose, so the next successful sync still counts
      // this device as behind and the newer copy wins.
      debugPrint('[sync] $key: push failed, will retry on next change: $e');
    }
  }

  /// Record that local storage changed at this instant without sending
  /// anything. Used when a device adopts the server's copy, so it is not
  /// immediately considered stale against the very thing it just took.
  static Future<void> markLocalFresh(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_localStampKey(key), DateTime.now().millisecondsSinceEpoch);
  }
}
