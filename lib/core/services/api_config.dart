import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

/// Central place for the backend base URL + the auth token the app holds.
///
/// The token is a Supabase Auth JWT (or your own) — the server's `verifyJwt`
/// reads `sub` as the user id. Set both at sign-in.
class ApiConfig {
  ApiConfig._();
  static final ApiConfig instance = ApiConfig._();

  /// Cloud server base URL. Override per-flavour (dev/stg/prod) — NOT localhost.
  /// e.g. 'https://api.ourmynd.app'
  String baseUrl = const String.fromEnvironment(
    'OURMYND_API',
    defaultValue: 'http://localhost:8080',
  );

  /// Current user's bearer token. Null until signed in.
  String? authToken;

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
