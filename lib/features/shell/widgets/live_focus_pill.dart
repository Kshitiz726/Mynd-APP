import 'package:flutter/material.dart';

/// The floating "23:58 Pomodoro" pill (mirrors the prototype's `#live-pill`).
/// Shown over every tab except the active-focus screen itself while a session
/// is running, so the user always knows time is ticking and can tap back in.
class LiveFocusPill extends StatelessWidget {
  const LiveFocusPill({super.key, required this.time, required this.modeName, required this.onTap});

  final String time;
  final String modeName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0E11),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFE0954E)),
            ),
            const SizedBox(width: 9),
            Text(
              time,
              style: const TextStyle(
                color: Color(0xFFE0954E),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              modeName,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
