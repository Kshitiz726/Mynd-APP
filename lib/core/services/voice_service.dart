import 'package:livekit_client/livekit_client.dart';

import 'realtime_service.dart';

/// Wraps the LiveKit audio session for a focus room's body-doubling voice.
///
/// Flow: ask the server (`voice_join`) for a token → connect to the SFU →
/// publish a muted mic track. Mute/PTT just toggle the local track; the visual
/// grid badge is broadcast separately via [RealtimeService.toggleMute].
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  Room? _room;
  bool get inCall => _room != null;

  /// Call after `voice_token` arrives from the server.
  Future<void> connect({required String url, required String token}) async {
    await disconnect();
    final room = Room(roomOptions: const RoomOptions(adaptiveStream: true));
    await room.connect(url, token);
    // Publish mic, but start muted - push-to-talk / explicit unmute enables it.
    await room.localParticipant?.setMicrophoneEnabled(false);
    _room = room;
  }

  /// Push-to-talk: enable the mic on press, disable on release.
  Future<void> setTalking(bool talking) async {
    await _room?.localParticipant?.setMicrophoneEnabled(talking);
  }

  /// Hold-to-mute toggle (non-PTT mode).
  Future<void> setMuted(bool muted) async {
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
  }

  Future<void> disconnect() async {
    if (_room == null) return;
    final r = _room;
    _room = null;
    try {
      await r?.disconnect();
      await r?.dispose();
    } catch (_) {}
  }
}
