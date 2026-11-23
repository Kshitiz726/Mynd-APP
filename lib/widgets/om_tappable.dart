import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/haptics.dart';
import '../providers/settings_provider.dart';

/// The haptic fired the instant a press is registered.
enum OmTapFeedback { none, light, medium, select, success }

/// Softens a press-scale towards 1.
///
/// Every call site in the app picked its own number between 0.84 and 0.99,
/// tuned by eye against the old fast, overshooting animation. Rather than
/// re-tune eighty of them by hand, this pulls each one 45% of the way back to
/// rest: the relative weighting the author intended is preserved - a small
/// icon button still depresses more than a full-width card - while the
/// absolute travel drops to something that feels like give rather than a
/// shove. 0.84 becomes 0.912, 0.96 becomes 0.978.
double softPress(double scale) => 1 - (1 - scale) * 0.55;

/// A universal tap target that gives every interactive surface in OurMynd the
/// same tactile, iOS-like response:
///
/// - **Press-in** scales the child down quickly (`pressedScale`, ~0.96).
/// - **Release** springs it back with a subtle overshoot ([Curves.easeOutBack]).
/// - A **haptic** fires on touch-down (configurable, gated by the global
///   haptics setting), so the buzz lands the moment your finger touches glass
///   rather than after the action resolves.
/// - Honours the "reduce motion" accessibility setting (no scaling, instant).
///
/// Use this in place of bare [GestureDetector]/[InkWell] for cards, tiles,
/// chips, nav items and icon buttons so the whole app shares one feel.
class OmTappable extends StatefulWidget {
  const OmTappable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.feedback = OmTapFeedback.select,
    this.pressedScale = 0.96,
    this.opaque = true,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final OmTapFeedback feedback;
  final double pressedScale;

  /// When true the whole bounding box is hit-testable (so taps land on padding,
  /// not just painted pixels).
  final bool opaque;
  final bool enabled;

  @override
  State<OmTappable> createState() => _OmTappableState();
}

class _OmTappableState extends State<OmTappable> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _fireHaptic() {
    switch (widget.feedback) {
      case OmTapFeedback.none:
        break;
      case OmTapFeedback.light:
        Haptics.light();
      case OmTapFeedback.medium:
        Haptics.medium();
      case OmTapFeedback.select:
        Haptics.select();
      case OmTapFeedback.success:
        Haptics.success();
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        context.select<SettingsProvider, bool>((s) => s.reduceMotion);

    final pressed = _pressed && _interactive && !reduceMotion;

    return GestureDetector(
      behavior: widget.opaque ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      onTapDown: _interactive
          ? (_) {
              _fireHaptic();
              _setPressed(true);
            }
          : null,
      onTapUp: _interactive ? (_) => _setPressed(false) : null,
      onTapCancel: _interactive ? () => _setPressed(false) : null,
      onTap: widget.enabled ? widget.onTap : null,
      onLongPress: widget.enabled ? widget.onLongPress : null,
      child: AnimatedScale(
        // Cushioned, not springy.
        //
        // This used to snap in over 90ms and come back on easeOutBack, which
        // overshoots: the control sank fast and then bounced past its resting
        // size. That reads as plastic. Softness is the opposite shape - the
        // press-in takes long enough to feel like give rather than a click,
        // and the release settles without passing the target, so nothing
        // twangs back at the finger.
        //
        // The travel is also shortened a touch at the call sites' expense:
        // see [softPress], which pulls any scale closer to 1. A big squash is
        // read as the widget being shoved; a small one is read as it yielding.
        scale: pressed ? softPress(widget.pressedScale) : 1.0,
        duration: Duration(milliseconds: pressed ? 140 : 320),
        curve: pressed ? Curves.easeOutSine : Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
