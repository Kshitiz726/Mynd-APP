import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// App-wide scroll behaviour that gives every list, sheet and page the same
/// fluid, iOS-style feel regardless of the platform it runs on:
///
/// - **Bouncing overscroll** with a soft rubber-band at the edges.
/// - **No Material overscroll glow** (the harsh blue/teal stretch).
/// - **No scrollbar** chrome by default - content floats.
/// - Trackpad + mouse-wheel drag enabled so it feels right on desktop/web too.
class OmScrollBehavior extends MaterialScrollBehavior {
  const OmScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
        decelerationRate: ScrollDecelerationRate.normal,
      );

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child; // No glow - the bounce is the feedback.

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child; // No scrollbar chrome.
}
