import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

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
  /// silence sits an order of magnitude below this. Only consulted when the
  /// meter actually reported something - see [_meterWorked].
  static const _silenceFloor = 0.035;

  /// True once the bridge has sent at least one non-zero loudness reading.
  ///
  /// An off-screen WebView gets its AudioContext suspended, so the analyser can
  /// sit at a flat zero for a whole recording that captured speech fine. That
  /// is unknown loudness, not measured silence, and the two must not be treated
  /// alike: doing so discarded every real recording.
  bool _meterWorked = false;

  /// Smallest clip worth sending to Whisper. A webm/opus header alone is a few
  /// hundred bytes; anything with speech in it clears this comfortably.
  static const _minClipBytes = 2048;

  /// Why the last [startRecording] failed, in words meant for the user.
  ///
  /// Without this the sheet could only say "microphone unavailable", which is
  /// the same sentence whether the OS grant is missing, the user chose "don't
  /// ask again", or the bridge was not up yet - three problems with three
  /// different fixes.
  String? lastError;
  bool _permanentlyDenied = false;

  /// True when the user picked "deny and don't ask again": the system dialog
  /// will not appear again, so the only way through is app settings.
  bool get micBlockedInSettings => _permanentlyDenied;

  /// Send the user to the OS page where the mic can be re-enabled.
  Future<void> openMicSettings() => openAppSettings();

  /// Start capturing the mic. [onLevel] receives loudness (0..1) from the bridge
  /// so the UI can react to the voice and detect pauses. Returns false on
  /// failure, with [lastError] set.
  Future<bool> startRecording({void Function(double level)? onLevel}) async {
    if (_recording) return true;
    lastError = null;
    _permanentlyDenied = false;

    // The OS grant comes first. RECORD_AUDIO is in the manifest, but on API 23+
    // that only means the app *may* ask - until the user says yes, getUserMedia
    // inside the bridge WebView fails, and it fails as silence rather than as an
    // error, which is what made this look like "the mic just never hears me".
    // The WebView's own onPermissionRequest cannot do this: it answers the web
    // permission, one layer above the Android one.
    if (!kIsWeb) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        _permanentlyDenied = status.isPermanentlyDenied;
        lastError = status.isPermanentlyDenied
            ? 'Microphone access is turned off for OurMynd. Open settings to '
                'switch it back on.'
            : 'OurMynd needs the microphone to hear you.';
        debugPrint('[voice] mic permission not granted: $status');
        return false;
      }
    }

    try {
      await _levelSub?.cancel();
      _peak = 0;
      _meterWorked = false;
      _levelSub = _puter.voiceLevel.listen((l) {
        if (l > 0) _meterWorked = true;
        _peak = math.max(_peak, l);
        onLevel?.call(l);
      });
      await _puter.startCapture();
      _recording = true;
      return true;
    } catch (e) {
      debugPrint('[voice] start failed: $e');
      lastError = 'Could not open the microphone. $e';
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
      debugPrint('[voice] captured ${bytes.length} bytes, peak=$_peak');

      // Nothing worth sending: an empty or truncated clip.
      if (bytes.length < _minClipBytes) {
        debugPrint('[voice] clip too small to be speech, skipping transcribe');
        return '';
      }

      // The loudness meter is NOT allowed to veto a real recording.
      //
      // It reads an AnalyserNode inside the bridge WebView, and that view is
      // deliberately zero-size and off-screen, so the browser suspends its
      // AudioContext and the analyser reports zeros - while MediaRecorder goes
      // on capturing perfectly good audio. Gating on `_peak < floor` therefore
      // threw away every word the user said on a real phone and reported it as
      // "didn't catch that", with the mic visibly live the whole time.
      //
      // Peak is kept for the orb's swell, and still used to skip a clip we can
      // positively measure as silent - but only when the meter actually
      // produced a reading. No reading means unknown, not silent.
      if (_meterWorked && _peak < _silenceFloor) {
        debugPrint('[voice] measured silence (peak=$_peak), skipping');
        return '';
      }

      final text = await GroqService.instance
          .transcribe(bytes, filename: 'audio.webm');
      debugPrint('[voice] transcript: "${text.isEmpty ? '<empty>' : text}"');
      return text;
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
