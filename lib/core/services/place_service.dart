import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where somebody is, to the nearest town.
///
/// Coarse on purpose. The only thing this feeds is a news search, which works
/// just as well on "Bristol" as on a street address, so asking the OS for
/// anything finer would be collecting precision the app has no use for. The
/// coordinates are never stored and never leave the device: only the town name
/// is kept, and only that is sent anywhere.
class PlaceService {
  PlaceService._();
  static final PlaceService instance = PlaceService._();

  static const _kPlace = 'om_place_name';

  String? _cached;

  /// The last known town, from memory or disk, without asking the OS.
  ///
  /// Kept so a denied permission, a flight-mode morning or a slow fix does not
  /// leave the feature with nothing: yesterday's town is almost always still
  /// today's, and a slightly stale place beats no place.
  Future<String?> lastKnown() async {
    if (_cached != null) return _cached;
    try {
      final p = await SharedPreferences.getInstance();
      return _cached = p.getString(_kPlace);
    } catch (e) {
      debugPrint('[place] cached read failed: $e');
      return null;
    }
  }

  /// Whether the OS will give us a location without showing a prompt.
  ///
  /// Lets a caller decide to ask at a moment that makes sense rather than
  /// having a permission dialog appear over whatever somebody was doing.
  Future<bool> get granted async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always ||
          p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Ask for the town, prompting for permission if [prompt] is set.
  ///
  /// Returns the last known town on every failure rather than null, so callers
  /// have one thing to handle instead of five.
  Future<String?> resolve({bool prompt = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return lastKnown();

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && prompt) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return lastKnown();
      }

      // Low accuracy and a short deadline: a town-level answer does not need a
      // GPS fix, and waiting on one would hold up the first line of the day.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final marks =
          await Geocoding().placemarkFromCoordinates(pos.latitude, pos.longitude);
      final name = _nameFrom(marks);
      if (name == null) return lastKnown();
      await _remember(name);
      return name;
    } catch (e) {
      debugPrint('[place] lookup failed: $e');
      return lastKnown();
    }
  }

  /// The most searchable name in a placemark.
  ///
  /// locality is the town and is what a news index understands. Falling back
  /// through the administrative areas rather than to the country, because
  /// "United Kingdom" as a news search returns national politics, which is the
  /// opposite of what somebody asked for when they said local.
  static String? _nameFrom(List<Placemark> marks) {
    for (final m in marks) {
      for (final candidate in [m.locality, m.subAdministrativeArea, m.administrativeArea]) {
        if (candidate != null && candidate.trim().isNotEmpty) {
          return candidate.trim();
        }
      }
    }
    return null;
  }

  Future<void> _remember(String name) async {
    _cached = name;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPlace, name);
    } catch (e) {
      debugPrint('[place] persist failed: $e');
    }
  }
}
