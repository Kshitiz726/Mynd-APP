import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Whether this code is running under `flutter test`.
///
/// Only for skipping things that have no platform implementation in a test
/// binding, such as an embedded webview. Never for changing what the app
/// actually does: a test that exercises different behaviour than the app ships
/// is worth less than no test.
///
/// `Platform.environment` is the documented way to detect this, and it is not
/// available on web, where there is no test binding to detect either.
final bool kTestMode =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
