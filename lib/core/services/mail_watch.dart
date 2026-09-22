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
/// Nothing here polls. There was a three minute repeating timer and it is gone:
/// a timer that runs forever whether or not anything is happening drains a
/// battery for nothing, keeps a mail socket opening all day, and is the kind of
/// thing that draws an App Review question nobody wants to be answering during
/// a release. Both halves are event driven instead. The watch looks when the
/// app launches and when it comes back to the foreground. A queued send arms
/// one timer, for that one message, at that one moment, and nothing ticks in
/// between.
///
/// The honest limit, stated once here rather than implied everywhere: iOS does
/// not let an app like this wake itself up on a schedule. So a queued message
/// goes out exactly on time when the app is open, and at the first moment it
/// is next opened otherwise. A local notification is registered for the due
/// time either way, so the user is told at the right moment even when the send
/// itself has to wait for them to come back. Doing better means a server
/// holding a mail credential, which is a much bigger promise than this app
/// makes about where that credential lives.
class MailWatch extends ChangeNotifier {
  MailWatch._();
  static final MailWatch instance = MailWatch._();

  static const _kWatching = 'om_mail_watching';
  static const _kLastSeen = 'om_mail_last_seen';
  static const _kQueue = 'om_mail_queue';

  /// The one-shot timer for the next queued message, or null when the queue is
  /// empty. Armed for a single moment, never repeating.
  Timer? _due;
  bool _watching = false;
  bool _busy = false;
  bool _sending = false;
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
    if (_watching) unawaited(_check());
    await runDue();
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
      // Mark everything currently in the inbox as already seen, so turning the
      // watch on does not immediately announce mail from last Tuesday.
      unawaited(_check(announce: false));
    }
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
    // A notification at the right moment, for the case where the app is not
    // running then. Deliberately not phrased as "sent": at the moment this
    // fires nothing has been sent, and a notification that claims otherwise is
    // the worst possible lie for this feature to tell.
    await _notify(() => NotificationService.instance.schedule(
          id: _dueNotificationId(m.id),
          title: 'Ready to send to ${m.to}',
          body: 'Open OurMynd and it goes out: ${m.subject}',
          at: m.at,
        ));
    debugPrint('[watch] queued ${m.id} for ${m.at}');
    await runDue();
  }

  /// Notifications are a courtesy, never a precondition.
  ///
  /// Permission can be refused, the plugin can be unavailable, and none of
  /// that is a reason to abandon a message somebody asked to have sent. A send
  /// that is skipped because a banner could not be drawn would be absurd.
  static Future<void> _notify(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('[watch] notification failed: $e');
    }
  }

  /// Two notifications per message, and they must not collide: one warning the
  /// message is due, one confirming it went.
  static int _dueNotificationId(String id) => id.hashCode & 0x7fffffff;
  static int _sentNotificationId(String id) => '$id-sent'.hashCode & 0x7fffffff;

  /// Wake up exactly once, for the next message that is due.
  ///
  /// One timer for one moment, rather than a repeating tick asking "is it time
  /// yet" all day. Re-armed whenever the queue changes, and cancelled outright
  /// when it empties.
  void _armNext() {
    _due?.cancel();
    _due = null;
    if (_queue.isEmpty) return;

    // Only messages still in the future get a timer.
    //
    // Anything already past is either about to be sent by the runDue that is
    // calling this, or has just failed to send and is being kept for another
    // try. Re-arming for a past time would mean an immediate retry, and since
    // that retry re-arms in its turn, one permanently failing message would
    // spin against the mail server for as long as the app stayed open. A
    // failure waits for the next launch or resume instead, which is a real
    // change of circumstances rather than the same attempt again.
    final now = DateTime.now();
    final upcoming = _queue.map((m) => m.at).where((t) => t.isAfter(now));
    if (upcoming.isEmpty) return;
    final next = upcoming.reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = next.difference(now);
    // Timer takes a 32 bit millisecond count on some platforms, and a message
    // queued for next month would silently fire immediately. Anything beyond a
    // day is left to the next launch or resume to pick up, which is the same
    // path a cold start already takes.
    if (wait > const Duration(days: 1)) return;
    debugPrint('[watch] next send in ${wait.inMinutes}m');
    _due = Timer(wait, () => unawaited(runDue()));
  }

  Future<bool> cancelSend(String id) async {
    final before = _queue.length;
    _queue.removeWhere((m) => m.id == id);
    if (_queue.length == before) return false;
    notifyListeners();
    await _persistQueue();
    await _notify(
        () => NotificationService.instance.cancel(_dueNotificationId(id)));
    _armNext();
    return true;
  }

  /// Send anything whose time has come, then arm the timer for the next one.
  ///
  /// Nothing here asks permission. The permission was given when the message
  /// was written and queued, and waking somebody at the moment it is due to ask
  /// them again would defeat the entire point of scheduling it.
  Future<void> runDue() async {
    if (_sending) return;
    _sending = true;
    try {
      final now = DateTime.now();
      final due = _queue.where((m) => !m.at.isAfter(now)).toList();
      for (final m in due) {
        final r = await MailService.instance.send(
          to: m.to,
          subject: m.subject,
          body: m.body,
        );
        debugPrint('[watch] scheduled send ${m.id}: ok=${r.ok}');

        // Only drop it once it has actually gone. A failed send stays queued,
        // so reconnecting an account is enough to make it happen rather than
        // the message being lost at the one moment nobody was watching.
        if (r.ok) {
          _queue.removeWhere((q) => q.id == m.id);
          await _notify(
              () => NotificationService.instance.cancel(_dueNotificationId(m.id)));
        }
        _sends.add(SentResult(mail: m, ok: r.ok, message: r.message));

        // Told at the moment it happens, not only in a conversation they may
        // not be looking at. A message going out under somebody's own name is
        // worth a notification whichever way it went.
        await _notify(() => NotificationService.instance.showNow(
              id: _sentNotificationId(m.id),
              title: r.ok ? 'Sent to ${m.to}' : 'Could not send to ${m.to}',
              body: r.ok ? m.subject : r.message,
            ));
      }
      if (due.isNotEmpty) {
        notifyListeners();
        await _persistQueue();
      }
    } finally {
      _sending = false;
    }
    _armNext();
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
    _due?.cancel();
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
