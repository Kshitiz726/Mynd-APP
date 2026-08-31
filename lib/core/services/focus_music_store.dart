import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/room_music.dart';
import '../utils/spotify_uri.dart';

/// The music a solo focus session is playing.
///
/// A room keeps this on the server, because everyone in it has to agree. A solo
/// session has nobody to agree with, so it lives on the device - but it is the
/// same shape and the same link handling, so the two cannot drift into
/// accepting different things.
///
/// Persisted so the link survives between sessions. Re-pasting a playlist every
/// time you sit down is exactly the friction this feature exists to remove.
class FocusMusicStore extends ChangeNotifier {
  FocusMusicStore._();
  static final FocusMusicStore instance = FocusMusicStore._();

  static const _kUri = 'om_focus_music_uri';
  static const _kTitle = 'om_focus_music_title';

  RoomMusic? _music;
  RoomMusic? get music => _music;

  /// Set when a paste is refused, cleared on the next accepted one.
  String? error;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final uri = p.getString(_kUri);
      if (uri != null && normaliseSpotifyUri(uri) != null) {
        _music = RoomMusic(
          uri: uri,
          title: p.getString(_kTitle),
          changedBy: '',
          changedAt: DateTime.now(),
        );
        notifyListeners();
      }
    } catch (e) {
      // A cache that will not load is not worth failing a focus session over.
      debugPrint('[focus-music] cached read failed: $e');
    }
  }

  /// Set what this session plays. Pass null to clear.
  Future<void> set(String? raw, {String? title}) async {
    if (raw == null) {
      _music = null;
      error = null;
      notifyListeners();
      await _persist(null, null);
      return;
    }
    // The same normaliser the room uses and the server enforces. Nothing is
    // stored raw, so a share link's `?si=` tracking token never lands on disk.
    final uri = normaliseSpotifyUri(raw);
    if (uri == null) {
      error = 'that is not a Spotify link';
      notifyListeners();
      return;
    }
    error = null;
    _music = RoomMusic(
      uri: uri,
      title: title,
      changedBy: '',
      changedAt: DateTime.now(),
    );
    notifyListeners();
    await _persist(uri, title);
  }

  Future<void> _persist(String? uri, String? title) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (uri == null) {
        await p.remove(_kUri);
        await p.remove(_kTitle);
      } else {
        await p.setString(_kUri, uri);
        if (title == null) {
          await p.remove(_kTitle);
        } else {
          await p.setString(_kTitle, title);
        }
      }
    } catch (e) {
      debugPrint('[focus-music] persist failed: $e');
    }
  }
}
