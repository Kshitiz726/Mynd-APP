import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/room_music.dart';
import '../utils/music_link.dart';
import 'music_title.dart';

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
      if (uri != null && normaliseMusicUri(uri) != null) {
        _music = RoomMusic(
          uri: uri,
          title: p.getString(_kTitle),
          changedBy: '',
          changedAt: DateTime.now(),
          // Null on purpose. startedAt is the ROOM's shared clock, and
          // positionAt() measures from it - so setting it here made a solo
          // session seek to "however long ago you picked this", which grows
          // without bound and silently lands past the end of any track shorter
          // than the session. A solo track has nobody to line up with and
          // starts at the beginning.
          startedAt: null,
        );
        notifyListeners();
        // Anything saved before titles existed, or saved while offline, has
        // no name yet. Filling it in on load means an existing listener is not
        // stuck looking at "Video . vnHTrx..." until they happen to re-paste.
        if (_music!.title == null) await _fillInTitle(uri);
      }
    } catch (e) {
      // A cache that will not load is not worth failing a focus session over.
      debugPrint('[focus-music] cached read failed: $e');
    }
  }

  /// Set what this session plays. Pass null to clear.
  ///
  /// The name is looked up afterwards rather than before, so pressing "set it"
  /// starts the music immediately: solo there is nobody to agree with, so a
  /// label that arrives a moment late costs nothing, and waiting on a network
  /// round trip to hear anything would cost a lot.
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
    final uri = normaliseMusicUri(raw);
    if (uri == null) {
      error = 'paste an audio, YouTube or Spotify link';
      notifyListeners();
      return;
    }
    error = null;
    _music = RoomMusic(
      uri: uri,
      title: title,
      changedBy: '',
      changedAt: DateTime.now(),
      startedAt: null,
    );
    notifyListeners();
    await _persist(uri, title);
    if (title == null) await _fillInTitle(uri);
  }

  /// Replace the id-based label with the track's real name once we know it.
  ///
  /// Guarded on the uri still being the current one: the lookup is slower than
  /// somebody changing their mind, and stamping a stale title onto whatever is
  /// playing now would be worse than no title at all.
  Future<void> _fillInTitle(String uri) async {
    final link = MusicLink.parse(uri);
    if (link == null) return;
    final name = await fetchMusicTitle(link);
    if (name == null || _music?.uri != uri) return;
    _music = RoomMusic(
      uri: uri,
      title: name,
      changedBy: '',
      changedAt: _music!.changedAt,
      startedAt: null,
    );
    notifyListeners();
    await _persist(uri, name);
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
