import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'realtime_service.dart';

/// Where the app's server lives, decided at runtime instead of at compile time.
///
/// The address used to be baked into the binary, so moving the server meant
/// shipping a new build and waiting on App Review, and every phone that had
/// not updated kept talking to a machine that was no longer there. Now the
/// app reads one small file on the website and uses the address in it, so a
/// move is a one line edit that every installed build picks up by itself.
///
/// **Why this is the most dangerous file in the app.** The address decided
/// here is where the session token goes on the very next request. Anyone who
/// can change that file can point every installed app at a server they own and
/// collect everybody's credentials, and nothing on the phone would look wrong.
/// So the file is treated as a hint from a source that could be compromised,
/// never as an instruction:
///
///  * https only, so the address cannot be downgraded or rewritten in transit;
///  * the host must be one of [_allowedHostSuffixes], so a stolen website or
///    GitHub account still cannot send anybody's token somewhere new - the
///    worst it can do is move traffic between hosts we already trust;
///  * only the origin is kept, so no path, query or credentials can be smuggled
///    in and prefixed onto every request the app makes;
///  * anything that fails those checks is ignored and the current address
///    stays, which means a corrupt or hostile file degrades to "no change"
///    rather than to "no app".
///
/// Moving to a host outside the allowlist is deliberately an app update. That
/// is the trade: the file can move traffic within a fence we chose in advance,
/// and it takes a signed release to move the fence.
class ServerDirectory {
  ServerDirectory._();
  static final ServerDirectory instance = ServerDirectory._();

  /// The last address that came from the file and passed [normalise].
  ///
  /// Not a secret - it is a public hostname, and it is read on the first frame
  /// before anything else is ready - so ordinary preferences rather than the
  /// keychain. It is validated again on the way out, so a tampered value on a
  /// rooted device buys nothing a hostile file could not already do.
  static const String _kCached = 'om_server_api';

  /// Overridable so a switch can be exercised against a file we serve
  /// ourselves. The live file is read by real installs, so tests must never
  /// point at it.
  static const String fileUrl = String.fromEnvironment(
    'OURMYND_SERVER_FILE',
    defaultValue: 'https://www.ourmynd.com/servers.json',
  );

  /// The exact Render services we run. Named one by one, not matched by
  /// `.onrender.com`, because onrender.com is shared hosting: anybody can
  /// create a service there in a minute. A suffix rule would have let whoever
  /// tampered with the file stand up `harvester.onrender.com` and collect
  /// every session, which is precisely the attack the allowlist exists to
  /// stop. Exact hosts mean the worst a hostile file can do is move traffic
  /// between servers we already own.
  static const List<String> _allowedHosts = [
    'ourmynd-server-3bvh.onrender.com',
    'ourmynd-server.onrender.com',
  ];

  /// Domains we control outright, where any subdomain is ours by definition.
  ///
  /// This is the escape hatch that keeps the exact list above from becoming a
  /// cage: point api.ourmynd.com at whichever server is current and the app can
  /// follow it anywhere, for ever, without a release - while nobody else can
  /// register a name under it.
  static const List<String> _allowedDomains = ['ourmynd.com'];

  /// Short on purpose. This runs before the first frame, and a server move is
  /// not worth making every launch wait on a slow network: the cached address
  /// is already applied by the time this starts, so a timeout costs nothing but
  /// a few minutes of staleness.
  static const Duration fetchTimeout = Duration(seconds: 2);

  /// How often a foreground return is allowed to re-read the file.
  static const Duration refreshInterval = Duration(minutes: 12);

  DateTime? _lastChecked;

  /// False when this build is pointed at a developer machine.
  ///
  /// A local build runs against `http://localhost` or a LAN address, and the
  /// whole point of that is to bypass the hosted server. Following the file
  /// would drag it straight back to production, so a non-https compiled
  /// address disables this service outright.
  static bool get followsFile =>
      Uri.tryParse(ApiConfig.compiledApi)?.scheme == 'https';

  /// The only way an address from the file becomes an address the app uses.
  ///
  /// Returns the bare origin, or null if the value fails any check. Pure and
  /// public so the rules are pinned by tests rather than by reading them.
  @visibleForTesting
  static String? normalise(String? raw) {
    if (raw == null) return null;
    final u = Uri.tryParse(raw.trim());
    if (u == null) return null;

    // https only. Never downgrade, whatever the file says.
    if (u.scheme != 'https') return null;
    if (!u.hasAuthority || u.host.isEmpty) return null;

    // `https://user:pass@host` would put credentials of the file's choosing
    // into every request the app makes.
    if (u.userInfo.isNotEmpty) return null;

    final host = u.host.toLowerCase();
    // The dot in `.$d` is what stops `evil-ourmynd.com` matching `ourmynd.com`.
    final allowed = _allowedHosts.contains(host) ||
        _allowedDomains.any((d) => host == d || host.endsWith('.$d'));
    if (!allowed) return null;

    // Origin only: a path here would be prefixed onto every endpoint, so
    // `https://ourmynd.com/../evil` style values are dropped rather than
    // cleaned up.
    final port = u.hasPort && u.port != 443 ? ':${u.port}' : '';
    return 'https://$host$port';
  }

  /// Apply the cached address, then try the file. Never throws.
  ///
  /// Ordering matters: the cache is applied synchronously-ish and before
  /// session restore, so the very first authenticated request already goes to
  /// the right server. The network fetch is best effort on top of that.
  Future<void> init() async {
    if (!followsFile) {
      debugPrint('[servers] compiled address is not https, staying on '
          '${ApiConfig.instance.baseUrl}');
      return;
    }

    final cached = normalise(await _readCache());
    if (cached != null && cached != ApiConfig.instance.baseUrl) {
      ApiConfig.instance.baseUrl = cached;
      debugPrint('[servers] using cached $cached');
    }

    // The fetch is allowed to outlive the timeout: a slow network must not
    // delay launch, but an address that arrives late is still worth having, so
    // the late completion applies itself rather than being thrown away.
    final pending = _fetchAndApply().catchError((Object e) {
      debugPrint('[servers] fetch failed, keeping ${ApiConfig.instance.baseUrl}: $e');
    });
    await pending.timeout(fetchTimeout, onTimeout: () {
      debugPrint('[servers] file slow, continuing on ${ApiConfig.instance.baseUrl}');
    });
  }

  /// Re-read the file on a foreground return, at most once per
  /// [refreshInterval]. Never throws.
  Future<void> refreshIfStale() async {
    if (!followsFile) return;
    final last = _lastChecked;
    if (last != null && DateTime.now().difference(last) < refreshInterval) {
      return;
    }
    try {
      await _fetchAndApply();
    } catch (e) {
      debugPrint('[servers] refresh failed: $e');
    }
  }

  Future<void> _fetchAndApply() async {
    // Stamped before the request, not after, so a server that fails or hangs
    // throttles the next attempt too. Otherwise a broken website would be
    // re-fetched on every single foreground.
    _lastChecked = DateTime.now();
    final res = await http.get(Uri.parse(fileUrl), headers: const {
      // The file changes rarely and matters immediately when it does.
      'Cache-Control': 'no-cache',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      debugPrint('[servers] file returned ${res.statusCode}');
      return;
    }

    // A file that is not the shape we expect is a broken deploy or someone
    // else's page, and either way it is not an instruction.
    final body = jsonDecode(res.body);
    if (body is! Map) return;
    final next = normalise(body['api'] as String?);
    if (next == null) {
      debugPrint('[servers] file carried no usable api address');
      return;
    }
    await _apply(next);
  }

  Future<void> _apply(String origin) async {
    if (origin == ApiConfig.instance.baseUrl) {
      await _writeCache(origin);
      return;
    }
    debugPrint('[servers] switching to $origin');
    ApiConfig.instance.baseUrl = origin;
    await _writeCache(origin);

    // The socket was built against the old address and will happily keep
    // retrying it forever, so the one piece of the app that captured the base
    // URL has to be told. Everything else reads it per request.
    RealtimeService.instance.onBaseUrlChanged();
  }

  Future<String?> _readCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_kCached);
    } catch (e) {
      debugPrint('[servers] could not read the cached address: $e');
      return null;
    }
  }

  Future<void> _writeCache(String origin) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kCached, origin);
    } catch (e) {
      debugPrint('[servers] could not cache the address: $e');
    }
  }
}
