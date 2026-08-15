import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';
import 'coach_memory_service.dart';

/// Gives every account its own local data on a shared device.
///
/// Everything personal in this app - today's schedule, tasks, goals, mood
/// history, the streak, coach memory, reminders - is stored in flat
/// `SharedPreferences` keys with no account attached to them. That was fine
/// while a device only ever had one user on it, and wrong the moment it had
/// two: signing in with a brand new Google account landed in a shell already
/// full of the previous person's schedule. Nothing had leaked from the server;
/// the new account was simply reading the same keys on disk.
///
/// The fix is a swap, not a delete. On a switch, the outgoing account's keys
/// are parked under its user id, and the incoming account's parked keys - if it
/// has been on this phone before - are put back in their place. Sign in as
/// someone new and you get an empty app; sign back in as yourself and your
/// schedule is exactly where you left it. Nothing is ever thrown away, so
/// handing the phone to somebody else can't cost you your data.
///
/// Doing it here rather than by namespacing keys in each provider is
/// deliberate: there are a dozen providers reading these keys, and one that
/// forgets to namespace brings the whole bug back. This way a provider added
/// tomorrow is covered without knowing this class exists - it just has to
/// prefix its key with `om_`, which they all already do.
class AccountScope {
  AccountScope._();

  /// The user id whose data is currently in the live keys.
  static const _kOwner = 'om_local_data_owner';

  /// Where a signed-out account's data waits: `omacct:<userId>:om_tasks`.
  ///
  /// Deliberately not starting with `om_`, so parked keys are never mistaken
  /// for live ones and re-parked under the next account.
  static const _park = 'omacct:';

  /// Data that has been on this device since before accounts were tracked. It
  /// can't be attributed to anyone, so it is parked out of the way under a name
  /// no user id will ever match, rather than deleted or handed to whoever
  /// happens to sign in next.
  static const _unclaimed = '${_park}_unclaimed:';

  /// The only two keys that stay put across a switch, because neither says
  /// anything about a person: whether Android's notification permission dialog
  /// has been shown (an OS-level, per-app fact - re-asking would just be a
  /// prompt loop), and the pointer to who owns the live data.
  static const _deviceKeys = <String>{_kOwner, 'om_notif_permission_asked'};

  /// The session is written immediately after a switch; leaving it out keeps
  /// the swap independent of that ordering.
  static const _sessionPrefix = 'om_session_';

  /// Called after the swap, so the app can rebuild everything still holding the
  /// previous account's data in memory. Set in main().
  static void Function()? onSwitched;

  /// Hand this device's live data to [userId], parking whoever had it before
  /// and unparking [userId]'s own data if it is here.
  ///
  /// Returns whether the live keys actually changed, which is the caller's cue
  /// that in-memory state has to be rebuilt too.
  static Future<bool> adopt(String userId) async {
    final p = await SharedPreferences.getInstance();
    final owner = p.getString(_kOwner);
    if (owner == userId) return false;

    final live = p.getKeys().where(_isPersonal).toList();
    final parkPrefix = owner == null ? _unclaimed : '$_park$owner:';
    for (final k in live) {
      await _move(p, from: k, to: '$parkPrefix$k');
    }

    final mine = '$_park$userId:';
    final returning = p.getKeys().where((k) => k.startsWith(mine)).toList();
    for (final k in returning) {
      await _move(p, from: k, to: k.substring(mine.length));
    }

    await p.setString(_kOwner, userId);

    // Held in memory by a singleton, so swapping its keys is not enough.
    await CoachMemoryService.instance.reload();

    // The outgoing account's reminders and alarms are armed with the OS and
    // would keep firing on a phone that is no longer showing their schedule.
    // The incoming account re-arms its own at startup (RemindersProvider is
    // built eagerly for exactly this reason).
    try {
      await NotificationService.instance.cancelAll();
    } catch (e) {
      debugPrint('[account] could not cancel pending notifications: $e');
    }

    debugPrint('[account] $owner -> $userId: parked ${live.length}, '
        'restored ${returning.length}');
    return live.isNotEmpty || returning.isNotEmpty;
  }

  static bool _isPersonal(String k) =>
      k.startsWith('om_') &&
      !_deviceKeys.contains(k) &&
      !k.startsWith(_sessionPrefix);

  /// Move one preference, whatever type it holds. `get` is untyped, so the
  /// value has to be written back through the setter that matches it - there is
  /// no generic `set`.
  static Future<void> _move(SharedPreferences p,
      {required String from, required String to}) async {
    final v = p.get(from);
    if (v is String) {
      await p.setString(to, v);
    } else if (v is bool) {
      await p.setBool(to, v);
    } else if (v is int) {
      await p.setInt(to, v);
    } else if (v is double) {
      await p.setDouble(to, v);
    } else if (v is List<String>) {
      await p.setStringList(to, v);
    } else {
      // Nothing we can write back, so leave the original alone rather than
      // silently dropping it.
      debugPrint('[account] skipped $from (${v.runtimeType})');
      return;
    }
    await p.remove(from);
  }
}
