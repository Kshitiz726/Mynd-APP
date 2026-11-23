/// Central place for the backend base URL + the auth token the app holds.
///
/// The token is a Supabase Auth JWT (or your own) - the server's `verifyJwt`
/// reads `sub` as the user id. Set both at sign-in.
class ApiConfig {
  ApiConfig._();
  static final ApiConfig instance = ApiConfig._();

  /// Cloud server base URL.
  ///
  /// The default is the **hosted** server, not localhost. It used to be
  /// `http://localhost:8080`, which meant that forgetting the dart-define did
  /// not fail loudly - it produced an app that looked fine, pointed at a
  /// machine that was not there, and failed every request once it left the
  /// developer's desk. That is exactly how a build reached the simulator
  /// talking to a laptop, and it is not a mistake worth leaving available to a
  /// release build.
  ///
  /// Local work overrides it explicitly (`./run-ios.local.sh` without
  /// `OURMYND_ENV=cloud`), so the safe value is the default and the risky one
  /// has to be asked for.
  ///
  /// Since build 20 this is only the last resort. [ServerDirectory] reads the
  /// live address from the website at launch, so this constant is what a phone
  /// uses before it has ever reached that file, or if the file is unreachable.
  ///
  /// It has to name whichever server is actually running, which is why it moves
  /// when that changes: it went to ourmynd-server-3bvh when the original host
  /// was suspended, and back again now that ourmynd-server is the one in
  /// service. Both are permanently in the allowlist, so the standby needs no
  /// release to be switched to - only `deploy/servers.json` changes for that.
  /// This constant is the one piece that does take a build, because a phone
  /// that has never reached the file has nothing else to go on.
  static const String hostedApi = 'https://ourmynd-server.onrender.com';

  /// What this binary was built with: the dart-define if one was passed, else
  /// [hostedApi].
  ///
  /// Kept separate from [baseUrl] because [baseUrl] moves at runtime now, and
  /// two questions need different answers: "where are we talking to right now"
  /// (baseUrl) and "was this build pointed at a developer machine"
  /// (compiledApi, which decides whether the server file is followed at all).
  static const String compiledApi = String.fromEnvironment(
    'OURMYND_API',
    defaultValue: hostedApi,
  );

  /// Where requests go right now. Mutable: [ServerDirectory] moves it when the
  /// website names a different server. Read per request through [rest], so a
  /// change takes effect on the next call rather than the next launch.
  String baseUrl = compiledApi;

  /// Current user's bearer token. Null until signed in.
  ///
  /// Short-lived now (30 minutes) rather than the month it used to last, so a
  /// copy lifted from a device is worth very little. [refreshToken] is what
  /// keeps the user signed in across that.
  String? authToken;

  /// Long-lived credential used only against /api/auth/refresh. Never sent to
  /// any other endpoint - see ApiClient._refreshSession.
  String? refreshToken;

  /// Current user id (the JWT `sub`), used to tell "me" from others in grids.
  String? userId;

  /// Current user's anonymous display name (e.g. "MellowOtter47") and handle
  /// (email for real Google sign-in). Set at sign-in for the profile/greeting.
  String? displayName;
  String? handle;

  Uri rest(String path) => Uri.parse('$baseUrl$path');
  Map<String, String> get authHeaders => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };
}
