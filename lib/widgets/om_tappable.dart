import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/haptics.dart';
import '../providers/settings_provider.dart';

/// The haptic fired the instant a press is registered.
enum OmTapFeedback { none, light, medium, select, success }

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
        scale: pressed ? widget.pressedScale : 1.0,
        // Quick, decisive press-in; springy, overshooting release.
        duration: Duration(milliseconds: pressed ? 90 : 260),
        curve: pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
