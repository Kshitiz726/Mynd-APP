import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Replicates the prototype's `toast()` — a brief floating message.
/// Implemented on top of [ScaffoldMessenger] so it respects safe areas and
/// queues correctly.
abstract final class Toast {
  static void show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 96),
          backgroundColor: context.omColors.text,
        ),
      );
  }
}
