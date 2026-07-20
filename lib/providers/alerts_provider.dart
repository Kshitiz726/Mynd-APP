import 'package:flutter/foundation.dart';

import '../core/services/api_client.dart';
import '../core/services/realtime_service.dart';
import '../models/community/chat_models.dart';

/// Backs the Alerts dashboard: incoming follow requests + the notification
/// inbox. Live updates arrive over the `notification` socket event, so a new
/// follow request or an accept lands without a refresh.
class AlertsProvider extends ChangeNotifier {
  final _api = ApiClient.instance;
  final _rt = RealtimeService.instance;

  List<FollowRequest> requests = [];
  List<AppNotification> notifications = [];
  List<AppNotification> localReminders = [];
  int unread = 0;
  bool loading = false;
  bool _wired = false;

  /// Last DM unlocked by accepting a request - the UI can pop straight into it.
  String? lastUnlockedDmId;

  List<AppNotification> get allNotifications {
    final combined = [...localReminders, ...notifications];
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return combined;
  }

  /// The Alerts dashboard is intentionally narrow: only post-comment alerts.
  /// (Follow requests are surfaced separately via [requests].) Everything else
  /// - reminders, room joins, sessions, messages - lives in the "you" tab's
  /// activity history via [allNotifications].
  List<AppNotification> get commentNotifications =>
      allNotifications.where((n) => n.kind == 'post_comment').toList();

  /// Unread badge count for the Alerts tab: pending follow requests plus unread
  /// comment alerts only - matching what the Alerts screen actually shows.
  int get alertsUnread =>
      requests.length + commentNotifications.where((n) => !n.read).length;

  void addLocalReminder(AppNotification n) {
    localReminders.insert(0, n);
    unread++;
    notifyListeners();
  }

  void init() {
    if (_wired) return;
    _wired = true;
    _rt.on('notification', (d) {
      final kind = d['kind'] as String?;
      // Cheap path: bump the badge + refetch the affected lists.
      unread++;
      if (kind == 'friend_request') {
        _api.fetchFollowRequests().then((r) {
          requests = r;
          notifyListeners();
        }).catchError((_) {});
      }
      refreshNotifications();
    });
  }

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([_api.fetchFollowRequests(), _api.fetchNotifications()]);
      requests = results[0] as List<FollowRequest>;
      final n = results[1] as ({List<AppNotification> items, int unread});
      notifications = n.items;
      unread = n.unread;
    } catch (e) {
      debugPrint('alerts load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refreshNotifications() async {
    try {
      final n = await _api.fetchNotifications();
      notifications = n.items;
      unread = n.unread;
      notifyListeners();
    } catch (_) {}
  }

  /// Accept → returns the DM conversation id (DM is provisioned server-side).
  Future<String?> accept(FollowRequest req) async {
    requests = requests.where((r) => r.userId != req.userId).toList();
    notifyListeners();
    try {
      final cid = await _api.respondFriendRequest(req.userId, true);
      lastUnlockedDmId = cid;
      return cid;
    } catch (e) {
      debugPrint('accept failed: $e');
      requests = [req, ...requests];
      notifyListeners();
      return null;
    }
  }

  Future<void> reject(FollowRequest req) async {
    requests = requests.where((r) => r.userId != req.userId).toList();
    notifyListeners();
    try {
      await _api.respondFriendRequest(req.userId, false);
    } catch (e) {
      debugPrint('reject failed: $e');
      requests = [req, ...requests];
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    unread = 0;
    notifications = [for (final n in notifications) n.copyWith(read: true)];
    localReminders = [for (final n in localReminders) n.copyWith(read: true)];
    notifyListeners();
    await _api.markNotificationsRead().catchError((_) {});
  }
}
