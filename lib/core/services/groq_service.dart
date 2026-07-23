import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// All communication with the Groq REST API lives here.
///
/// Two modes:
///   [streamCompletion] - Server-Sent Events. Yields token chunks as they
///     arrive. Used for every live coaching turn so the UI feels immediate.
///   [complete]         - Plain blocking POST. Used for low-stakes internal
///     work like memory summarisation, where streaming adds no value.
class GroqService {
  GroqService._();
  static final GroqService instance = GroqService._();

  // ─── Config ───────────────────────────────────────────────────────────────

  /// Provided at build/run time via `--dart-define=GROQ_API_KEY=...`.
  /// Never hard-code the key - it must not be committed to source control.
  static const _apiKey = String.fromEnvironment('GROQ_API_KEY');
  static const _endpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Primary model: fast, high-quality for live chat.
  static const _chatModel = 'llama-3.3-70b-versatile';

  /// Lightweight model for summarisation (saves tokens).
  static const _summaryModel = 'llama-3.1-8b-instant';

  static const _chatMaxTokens = 512;
  static const _summaryMaxTokens = 300;

  final _client = http.Client();

  // ─── Streaming ────────────────────────────────────────────────────────────

  /// Streams token-by-token chunks from Groq.
  ///
  /// [messages] must already be fully assembled by [CoachPromptBuilder].
  /// Throws [GroqException] on non-200 responses.
  Stream<String> streamCompletion(
    List<Map<String, String>> messages,
  ) async* {
    final request = http.Request('POST', Uri.parse(_endpoint));
    request.headers.addAll({
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode({
      'model': _chatModel,
      'messages': messages,
      'temperature': 0.85,
      'top_p': 0.95,
      'max_tokens': _chatMaxTokens,
      'stream': true,
    });

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw GroqException(
        'Groq API returned ${response.statusCode}: $body',
        statusCode: response.statusCode,
      );
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final payload = line.substring(6).trim();
      if (payload == '[DONE]') break;

      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final delta =
            (json['choices'] as List?)?.firstOrNull?['delta']
                as Map<String, dynamic>?;
        final chunk = delta?['content'] as String?;
        if (chunk != null && chunk.isNotEmpty) yield chunk;
      } catch (_) {
        // Malformed SSE chunk - skip silently.
      }
    }
  }

  // ─── Transcription (Whisper) ──────────────────────────────────────────────

  static const _transcribeEndpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  /// Fast, cloud speech-to-text. Turbo Whisper is quick and cheap; it works on
  /// emulators (which have no on-device recogniser) as long as the mic captured
  /// real audio. Returns the transcript, or '' when nothing intelligible was
  /// heard.
  Future<String> transcribe(
    List<int> bytes, {
    String filename = 'audio.m4a',
    String model = 'whisper-large-v3-turbo',
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(_transcribeEndpoint))
      ..headers['Authorization'] = 'Bearer $_apiKey'
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      // temperature 0 + a fixed language make Whisper far less likely to invent
      // filler ("Thank you.", "you") when the audio is quiet.
      ..fields['temperature'] = '0'
      ..fields['language'] = 'en'
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      throw GroqException(
        'Groq transcription returned ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final text = ((json['text'] ?? '') as String).trim();
    // Whisper fills silence with a handful of stock phrases lifted from its
    // training on captioned video. Treat those as "heard nothing".
    if (_isLikelySilence(text)) return '';
    return text;
  }

  static final _silenceFillers = <String>{
    'thank you', 'thank you.', 'thank you very much', 'thank you very much.',
    'thanks for watching', 'thanks for watching.', 'thanks for watching!',
    'thank you for watching', 'thank you for watching.', 'please subscribe',
    'you', 'bye', 'bye.', 'bye bye', '.', '..', '...',
  };

  static bool _isLikelySilence(String t) {
    final l = t.toLowerCase().trim();
    if (l.isEmpty) return true;
    return _silenceFillers.contains(l);
  }

  // ─── Blocking ─────────────────────────────────────────────────────────────

  /// Non-streaming completion - for summarisation and housekeeping tasks.
  Future<String> complete(List<Map<String, String>> messages) async {
    final response = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': _summaryModel,
        'messages': messages,
        'temperature': 0.3, // low for factual summaries
        'max_tokens': _summaryMaxTokens,
        'stream': false,
      }),
    );

    if (response.statusCode != 200) {
      throw GroqException(
        'Groq API returned ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['choices'][0]['message']['content'] as String;
  }

  void dispose() => _client.close();
}

class GroqException implements Exception {
  const GroqException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'GroqException($statusCode): $message';
}
