import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';

/// A side panel that pushes the app aside instead of covering it.
///
/// Flutter's own [Drawer] slides a sheet over the screen and dims what is
/// behind it. The reference does the opposite: the whole app, bottom nav and
/// all, slides to the right and shrinks a little, and the panel is revealed
/// underneath it. That is why this exists rather than a Scaffold drawer, and
/// it is also why it wraps the shell rather than the chat screen: the nav bar
/// has to travel with the rest of the app, and it lives a level above chat.
///
/// The panel is painted once, at full width, and never moves. Only the app
/// moves. That keeps the open gesture cheap (one transform, no relayout) and
/// means the panel is already in place the instant a drag starts, rather than
/// being built on the first frame of the animation.
class OmPushDrawer extends StatefulWidget {
  const OmPushDrawer({
    super.key,
    required this.panel,
    required this.child,
    this.dragEnabled = true,
    this.widthFactor = 0.82,
  });

  /// What is revealed underneath.
  final Widget panel;

  /// The app.
  final Widget child;

  /// Whether an edge drag can open it.
  ///
  /// False on tabs that are not the chat: this panel is the chat's index, and
  /// a horizontal swipe on a week rail or a timeline means something else
  /// there. Closing by drag stays on regardless, so nobody is ever stuck.
  final bool dragEnabled;

  final double widthFactor;

  /// The nearest push drawer, for `open()` / `close()` from a button.
  static OmPushDrawerState? of(BuildContext context) =>
      context.findAncestorStateOfType<OmPushDrawerState>();

  @override
  State<OmPushDrawer> createState() => OmPushDrawerState();
}

class OmPushDrawerState extends State<OmPushDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );

  /// Set while a drag is in progress, so [_width] is read from the same layout
  /// the drag started in.
  double _width = 0;

  bool get isOpen => _c.value > 0.5;

  /// 0 closed, 1 fully open. Exposed so a test can assert on the travel rather
  /// than on pixel positions, which depend on the surface size.
  double get progress => _c.value;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void open() {
    Haptics.light();
    _c.forward();
  }

  void close() => _c.reverse();

  void toggle() => isOpen ? close() : open();

  void _onDragUpdate(DragUpdateDetails d) {
    if (_width == 0) return;
    _c.value += d.primaryDelta! / _width;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_width == 0) return;
    // Velocity wins over position: a quick flick should open or close even if
    // the finger never crossed halfway, which is how every other sheet in the
    // app behaves.
    final v = d.velocity.pixelsPerSecond.dx / _width;
    if (v.abs() > 1.0) {
      _c.fling(velocity: v);
    } else {
      _c.value > 0.5 ? _c.forward() : _c.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth * widget.widthFactor;

        return ColoredBox(
          color: c.bg,
          // The system back gesture closes the panel before it leaves the
          // screen. Without this, swiping back with the panel out would look
          // like the app had quit while the panel was still showing.
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) => PopScope(
              canPop: _c.value == 0,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) close();
              },
              child: child!,
            ),
            child: Stack(
            children: [
              // Underneath, always. Ignored while closed so a stray tap cannot
              // land on a panel nobody can see.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _width,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, child) => IgnorePointer(
                    ignoring: _c.value == 0,
                    child: Opacity(
                      // Fades in over the first third of the travel so the
                      // panel does not read as a slab appearing under the app.
                      opacity: Curves.easeOut.transform(
                        (_c.value * 2.2).clamp(0.0, 1.0),
                      ),
                      child: child,
                    ),
                  ),
                  child: widget.panel,
                ),
              ),

              AnimatedBuilder(
                animation: _c,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(_c.value);
                  // The same three wrappers at every value, including zero.
                  //
                  // Returning `child` bare while closed looks like a free
                  // optimisation and is not: the first pixel of a drag moves t
                  // off zero, this branch swaps to a different widget at the
                  // same slot, the layer below is rebuilt from scratch, and the
                  // drag recognizer that was mid-gesture goes with it. The
                  // panel would travel exactly one frame and stop. Clip.none
                  // is what keeps the closed case free instead.
                  return Transform.translate(
                    offset: Offset(_width * t, 0),
                    child: Transform.scale(
                      scale: 1 - 0.06 * t,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30 * t),
                        clipBehavior: t == 0 ? Clip.none : Clip.antiAlias,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _AppLayer(
                  controller: _c,
                  dragEnabled: widget.dragEnabled,
                  onDragUpdate: _onDragUpdate,
                  onDragEnd: _onDragEnd,
                  onTapToClose: close,
                  child: widget.child,
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}

/// The app, plus the gestures that move it and the veil that says it is parked.
class _AppLayer extends StatelessWidget {
  const _AppLayer({
    required this.controller,
    required this.dragEnabled,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTapToClose,
    required this.child,
  });

  final AnimationController controller;
  final bool dragEnabled;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;
  final VoidCallback onTapToClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, app) {
        final open = controller.value > 0;
        return Stack(
          children: [
            // Blocked while the panel is out: the app is visible but parked,
            // and letting a tap through would mean pressing a button you can
            // only half see.
            AbsorbPointer(absorbing: open, child: app),

            // One detector, always, whose size is what changes: a narrow strip
            // down the left edge while closed, the whole parked app once open.
            //
            // It has to be the same widget in the same slot in both states.
            // Two branches here meant that the instant an edge drag moved the
            // value off zero, this rebuilt into a *different* GestureDetector,
            // the original recognizer was disposed mid-gesture, and the drag
            // was cancelled - so the panel could only ever be opened by the
            // button, and the edge swipe did nothing at all.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              right: open ? 0 : null,
              width: open ? null : 22,
              child: GestureDetector(
                behavior:
                    open ? HitTestBehavior.opaque : HitTestBehavior.translucent,
                // Tap anywhere on the parked app to put it back. It is the only
                // way out for somebody who opened this by accident.
                onTap: open ? onTapToClose : null,
                onHorizontalDragUpdate:
                    dragEnabled || open ? onDragUpdate : null,
                onHorizontalDragEnd: dragEnabled || open ? onDragEnd : null,
                child: ColoredBox(
                  color:
                      Colors.black.withValues(alpha: 0.28 * controller.value),
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
