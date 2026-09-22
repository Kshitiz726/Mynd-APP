import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';
import 'mail_service.dart';

/// Keeping an eye on the inbox, and sending things later.
///
/// Both halves are the same shape: something the user asked for in
/// conversation that has to happen when they are not looking at the screen.
///
/// The honest limit, stated once here rather than implied everywhere: iOS does
/// not let an app like this run on a schedule in the background. So the watch
/// polls while the app is alive and catches up the moment it is reopened, and
/// a scheduled send fires on time if the app is running and on the next open
/// if it is not. A local notification is registered for a scheduled send as
/// well, so the user is told at the right moment even when the send itself has
/// to wait for them to come back. Anything more than that needs a server that
/// holds a mail credential, which is a considerably bigger promise than this
/// app currently makes about where that credential lives.
class MailWatch extends ChangeNotifier {
  MailWatch._();
  static final MailWatch instance = MailWatch._();

  static const _kWatching = 'om_mail_watching';
  static const _kLastSeen = 'om_mail_last_seen';
  static const _kQueue = 'om_mail_queue';

  /// Long enough not to hammer the mailbox, short enough that "tell me when
  /// something lands" is not a lie. IMAP IDLE would be better and is a much
  /// larger change: it needs a socket held open across lifecycle events.
  static const _every = Duration(minutes: 3);

  Timer? _poll;
  bool _watching = false;
  bool _busy = false;
  String? _lastSeen;
  final List<ScheduledMail> _queue = [];

  bool get watching => _watching;
  List<ScheduledMail> get queue => List.unmodifiable(_queue);

  /// New mail arrived. The chat listens to this and says something.
  final StreamController<List<MailSummary>> _arrivals =
      StreamController<List<MailSummary>>.broadcast();
  Stream<List<MailSummary>> get arrivals => _arrivals.stream;

  /// A queued message went out, or could not.
  final StreamController<SentResult> _sends =
      StreamController<SentResult>.broadcast();
  Stream<SentResult> get sends => _sends.stream;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _watching = p.getBool(_kWatching) ?? false;
      _lastSeen = p.getString(_kLastSeen);
      _queue
        ..clear()
        ..addAll(((jsonDecode(p.getString(_kQueue) ?? '[]') as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ScheduledMail.fromJson(m.cast<String, dynamic>()))
            .whereType<ScheduledMail>());
    } catch (e) {
      debugPrint('[watch] could not restore: $e');
    }
    debugPrint('[watch] watching=$_watching queued=${_queue.length}');
    if (_watching) _start();
    unawaited(runDue());
  }

  // ─── Watching ─────────────────────────────────────────────────────────────

  Future<void> setWatching(bool on) async {
    if (_watching == on) return;
    _watching = on;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kWatching, on);
    } catch (_) {/* still on for this session */}
    if (on) {
      _start();
      // Mark everything currently in the inbox as already seen, so turning the
      // watch on does not immediately announce mail from last Tuesday.
      unawaited(_check(announce: false));
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _start() {
    _poll?.cancel();
    _poll = Timer.periodic(_every, (_) => _check());
  }

  /// Called when the app comes back to the foreground.
  Future<void> onResumed() async {
    await runDue();
    if (_watching) await _check();
  }

  Future<void> _check({bool announce = true}) async {
    if (_busy || !_watching || !MailService.instance.canRead) return;
    _busy = true;
    try {
      final msgs = await MailService.instance.recent(limit: 8, unreadOnly: true);
      if (msgs.isEmpty) return;

      // Newest first. Everything above the last one we announced is new.
      final newest = _keyOf(msgs.first);
      if (_lastSeen == null) {
        await _remember(newest);
        return;
      }
      final fresh = <MailSummary>[];
      for (final m in msgs) {
        if (_keyOf(m) == _lastSeen) break;
        fresh.add(m);
      }
      if (fresh.isEmpty) return;
      await _remember(newest);
      debugPrint('[watch] ${fresh.length} new');

      if (!announce) return;
      _arrivals.add(fresh);
      await NotificationService.instance.showNow(
        id: 'mail-watch'.hashCode & 0x7fffffff,
        title: fresh.length == 1 ? 'New email' : '${fresh.length} new emails',
        body: fresh.length == 1
            ? '${fresh.first.from}: ${fresh.first.subject}'
            : fresh.take(2).map((m) => m.from).join(', '),
      );
    } catch (e) {
      debugPrint('[watch] check failed: $e');
    } finally {
      _busy = false;
    }
  }

  /// Identity of a message for "have I already told them about this".
  /// Sender plus subject plus date, because IMAP UIDs are per mailbox and this
  /// has to survive the mailbox being reselected.
  static String _keyOf(MailSummary m) => '${m.date}|${m.from}|${m.subject}';

  Future<void> _remember(String key) async {
    _lastSeen = key;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLastSeen, key);
    } catch (_) {/* next check will try again */}
  }

  // ─── Sending later ────────────────────────────────────────────────────────

  Future<void> scheduleSend(ScheduledMail m) async {
    _queue.add(m);
    notifyListeners();
    await _persistQueue();
    // A notification at the right moment, whether or not the app is alive to
    // do the sending itself.
    await NotificationService.instance.schedule(
      id: m.id.hashCode & 0x7fffffff,
      title: 'Email to ${m.to}',
      body: 'Open OurMynd to let it go out: ${m.subject}',
      at: m.at,
    );
    debugPrint('[watch] queued ${m.id} for ${m.at}');
    unawaited(runDue());
  }

  Future<bool> cancelSend(String id) async {
    final before = _queue.length;
    _queue.removeWhere((m) => m.id == id);
    if (_queue.length == before) return false;
    notifyListeners();
    await _persistQueue();
    await NotificationService.instance.cancel(id.hashCode & 0x7fffffff);
    return true;
  }

  /// Send anything whose time has come, and arm a timer for the next one.
  Future<void> runDue() async {
    final now = DateTime.now();
    final due = _queue.where((m) => !m.at.isAfter(now)).toList();
    for (final m in due) {
      final r = await MailService.instance.send(
        to: m.to,
        subject: m.subject,
        body: m.body,
      );
      debugPrint('[watch] scheduled send ${m.id}: ok=${r.ok}');
      // Only drop it once it has actually gone. A failed send stays queued so
      // reconnecting an account is enough to make it happen, rather than the
      // message being silently lost at the one moment nobody was watching.
      if (r.ok) {
        _queue.removeWhere((q) => q.id == m.id);
        await NotificationService.instance.cancel(m.id.hashCode & 0x7fffffff);
      }
      _sends.add(SentResult(mail: m, ok: r.ok, message: r.message));
    }
    if (due.isNotEmpty) {
      notifyListeners();
      await _persistQueue();
    }
  }

  Future<void> _persistQueue() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kQueue, jsonEncode(_queue.map((m) => m.toJson()).toList()));
    } catch (e) {
      debugPrint('[watch] could not save the queue: $e');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _arrivals.close();
    _sends.close();
    super.dispose();
  }
}

/// A message waiting for its moment.
class ScheduledMail {
  ScheduledMail({
    required this.id,
    required this.to,
    required this.subject,
    required this.body,
    required this.at,
  });

  final String id;
  final String to;
  final String subject;
  final String body;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'to': to,
        'subject': subject,
        'body': body,
        'at': at.toIso8601String(),
      };

  static ScheduledMail? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final to = j['to'] as String?;
    final at = DateTime.tryParse((j['at'] as String?) ?? '');
    if (id == null || to == null || at == null) return null;
    return ScheduledMail(
      id: id,
      to: to,
      subject: (j['subject'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      at: at,
    );
  }
}

class SentResult {
  const SentResult({required this.mail, required this.ok, required this.message});

  final ScheduledMail mail;
  final bool ok;
  final String message;
}
