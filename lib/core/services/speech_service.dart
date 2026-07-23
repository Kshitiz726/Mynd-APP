import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'groq_service.dart';
import 'puter_service.dart';

/// Voice input, the reliable way: capture the mic in the Puter bridge WebView,
/// then transcribe the clip with Groq Whisper.
///
/// On-device recognisers (`speech_to_text`) simply are not present on most
/// Android emulators, which is why "talk to Mynd" kept saying "didn't catch
/// that": the recogniser errored the instant it started. And Puter's own
/// speech-to-text is not dependable. The bridge WebView already records audio
/// (a secure localhost context with the mic granted), so we reuse it purely as
/// a recorder and send the bytes to Groq's Whisper endpoint, which transcribes
/// on an emulator and a phone alike. Puter still speaks the reply back.
///
/// One shared instance so the mic is never opened twice at once.
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final PuterService _puter = PuterService.instance;
  bool _recording = false;
  StreamSubscription<double>? _levelSub;

  /// Loudest level seen during the current recording. When this stays tiny the
  /// mic captured silence (e.g. an emulator with no host audio wired), and
  /// sending that to Whisper only yields hallucinated filler, so we skip it.
  double _peak = 0;
  double get peakLevel => _peak;

  bool get isRecording => _recording;

  /// A level below which a whole recording is treated as silence. Kept low so a
  /// quiet mic (an emulator's, typically) still counts as real speech; true
  /// silence sits an order of magnitude below this.
  static const _silenceFloor = 0.035;

  /// Start capturing the mic. [onLevel] receives loudness (0..1) from the bridge
  /// so the UI can react to the voice and detect pauses. Returns false on
  /// failure.
  Future<bool> startRecording({void Function(double level)? onLevel}) async {
    if (_recording) return true;
    try {
      await _levelSub?.cancel();
      _peak = 0;
      _levelSub = _puter.voiceLevel.listen((l) {
        _peak = math.max(_peak, l);
        onLevel?.call(l);
      });
      await _puter.startCapture();
      _recording = true;
      return true;
    } catch (e) {
      debugPrint('[voice] start failed: $e');
      await _levelSub?.cancel();
      _levelSub = null;
      return false;
    }
  }

  /// Stop recording and transcribe the clip. Returns the text, or '' when
  /// nothing intelligible was captured (silence or a failed capture).
  Future<String> stopAndTranscribe() async {
    if (!_recording) return '';
    _recording = false;
    await _levelSub?.cancel();
    _levelSub = null;
    try {
      final bytes = await _puter.stopCapture();
      // Too small to be speech, or never got loud enough to be anything but
      // room noise: don't hand silence to Whisper.
      if (bytes.length < 2048 || _peak < _silenceFloor) return '';
      return await GroqService.instance
          .transcribe(bytes, filename: 'audio.webm');
    } catch (e) {
      debugPrint('[voice] transcription failed: $e');
      return '';
    }
  }

  /// Abandon the current recording without transcribing.
  Future<void> cancel() async {
    _recording = false;
    await _levelSub?.cancel();
    _levelSub = null;
    _puter.cancelCapture();
  }
}
