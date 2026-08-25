import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/api_client.dart';
import '../core/services/api_config.dart';

/// Whether this account has agreed to us processing health-related information,
/// and the single place anything in the app asks that question.
///
/// A singleton *and* a [ChangeNotifier]. Settings and the onboarding screen
/// need to rebuild when the answer changes, which wants a provider; the gate in
/// [StateSync] and the coach's context builder are plain static code with no
/// [BuildContext] to read one from, which wants a singleton. Splitting it into
/// two objects would have given the app two answers to a question that must
/// only ever have one.
///
/// The server is the source of truth - it holds the evidence and it is what
/// enforces the gate on writes. What is kept here is a cache, so that the first
/// frame after launch and every offline moment still gates correctly instead of
/// waiting on a network round trip.
///
/// **It fails closed.** Before the first successful fetch, and whenever the
/// answer cannot be established, [granted] is false. Getting this backwards
/// would mean an unknown state processed health data by default, which is the
/// one failure mode the policy has no answer for.
class HealthConsentProvider extends ChangeNotifier {
  HealthConsentProvider._();
  static final HealthConsentProvider instance = HealthConsentProvider._();

  static const _kGranted = 'om_health_consent_granted';
  static const _kDecidedAt = 'om_health_consent_decided_at';
  static const _kVersion = 'om_health_consent_version';

  /// null = never answered (or answered against a policy version that has since
  /// been superseded), true = agreed, false = declined or withdrawn.
  bool? _granted;
  bool? get answer => _granted;

  DateTime? _decidedAt;

  /// When they last answered, either way. Shown in Settings.
  DateTime? get decidedAt => _decidedAt;

  String? _policyVersion;

  /// The policy version their stored answer was given against.
  String? get policyVersion => _policyVersion;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// The gate. Health-related data may be processed only when this is true.
  bool get granted => _granted == true;

  /// True when the stored answer is absent: never asked, or asked against
  /// wording that no longer stands.
  ///
  /// This is about the *record*, not about whether to interrupt someone. Use
  /// [mustAsk] for that.
  bool get needsDecision => _granted == null;

  /// Whether the *server* has confirmed the current answer, as opposed to it
  /// having come from this device's cache or from nothing at all.
  bool _confirmedByServer = false;

  /// Whether to put the consent question in front of the user right now.
  ///
  /// Deliberately stricter than [needsDecision], and the difference matters:
  /// this asks only when the server has actually told us there is no answer on
  /// file. An unanswered *question* and an unreachable *server* look identical
  /// from the cache, and conflating them is how a consent screen turns into a
  /// lock-out - the screen appears, the answer cannot be recorded because the
  /// server is the thing that is down, and the feature behind it is gone until
  /// connectivity returns.
  ///
  /// So the two axes are separated. Access fails **open**: if we cannot
  /// establish the answer, the app stays usable and the question waits for a
  /// moment when it can actually be answered. Processing still fails
  /// **closed**: [granted] is false throughout, so nothing health-related is
  /// sent or stored while the answer is unknown. Being unable to ask is never
  /// a reason to assume yes, and it is never a reason to take the app away.
  bool get mustAsk => needsDecision && _confirmedByServer;

  /// They were asked and said no. Distinct from [needsDecision], because the
  /// app must not keep asking someone who has already answered.
  bool get declined => _granted == false;

  /// Read the cached answer from disk. Called during boot, before the first
  /// frame, so nothing gates on a null that a disk read would have filled in.
  Future<void> loadCached() async {
    try {
      final p = await SharedPreferences.getInstance();
      // containsKey rather than a bool getter with a default: "absent" is a
      // third state here and a default would collapse it into "declined",
      // which would silently stop the app ever asking.
      _granted = p.containsKey(_kGranted) ? p.getBool(_kGranted) : null;
      final at = p.getString(_kDecidedAt);
      _decidedAt = at == null ? null : DateTime.tryParse(at);
      _policyVersion = p.getString(_kVersion);
    } catch (e) {
      debugPrint('[consent] cached read failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Ask the server. The answer it gives replaces the cache, including the case
  /// where the policy has moved on and a previously granted consent comes back
  /// as undecided.
  Future<void> refresh() async {
    if (ApiConfig.instance.authToken == null) return;
    try {
      final j = await ApiClient.instance.fetchHealthConsent();
      await _apply(j);
    } catch (e) {
      // Leave the cache in place. A server we cannot reach is not a withdrawal,
      // and treating it as one would silently disable the coach's context for
      // anyone on a bad connection.
      debugPrint('[consent] refresh failed, keeping cached answer: $e');
    }
  }

  /// Record agreement. [source] is 'onboarding' or 'settings' and lands in the
  /// audit trail, because the policy's promise is partly about *where* the
  /// question was put.
  Future<void> grant({required String source}) async {
    final j = await ApiClient.instance.setHealthConsent(granted: true, source: source);
    await _apply(j);
  }

  /// Record a decline, or a withdrawal of consent already given. The same call:
  /// to the record they are the same fact, that as of now this account does not
  /// agree, and the audit trail already distinguishes them by what came before.
  Future<void> withdraw({required String source}) async {
    final j = await ApiClient.instance.setHealthConsent(granted: false, source: source);
    await _apply(j);
  }

  /// Erase the health-related data already stored on the account. Separate from
  /// [withdraw] on purpose - see the route's own comment.
  Future<int> deleteStoredData() => ApiClient.instance.deleteHealthData();

  /// Forget the cached answer. Called when the signed-in account changes, so
  /// the next account on this device is never gated by the previous one's
  /// decision - in either direction.
  Future<void> clear() async {
    _granted = null;
    _decidedAt = null;
    _policyVersion = null;
    // The incoming account has not been looked up yet, so nothing is confirmed
    // about it. Leaving this set would ask the new account the question on the
    // strength of a lookup done for the previous one.
    _confirmedByServer = false;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kGranted);
      await p.remove(_kDecidedAt);
      await p.remove(_kVersion);
    } catch (e) {
      debugPrint('[consent] clear failed: $e');
    }
  }

  Future<void> _apply(Map<String, dynamic> j) async {
    // Only reached from a call the server actually answered, which is what
    // makes it safe to interrupt someone with the question. See [mustAsk].
    _confirmedByServer = true;
    _granted = j['granted'] as bool?;
    final at = j['decidedAt'] as String?;
    _decidedAt = at == null ? null : DateTime.tryParse(at);
    _policyVersion = j['policyVersion'] as String?;
    _loaded = true;
    notifyListeners();

    try {
      final p = await SharedPreferences.getInstance();
      final g = _granted;
      if (g == null) {
        await p.remove(_kGranted);
      } else {
        await p.setBool(_kGranted, g);
      }
      final d = _decidedAt;
      if (d == null) {
        await p.remove(_kDecidedAt);
      } else {
        await p.setString(_kDecidedAt, d.toIso8601String());
      }
      final v = _policyVersion;
      if (v == null) {
        await p.remove(_kVersion);
      } else {
        await p.setString(_kVersion, v);
      }
    } catch (e) {
      debugPrint('[consent] cache write failed: $e');
    }
  }
}
