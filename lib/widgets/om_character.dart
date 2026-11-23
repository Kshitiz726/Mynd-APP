import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// The coach, drawn rather than photographed, so it can actually move.
///
/// The avatar used to be a PNG of the character with a transform on it: the
/// whole picture slid up and down and scaled a little. That is the only motion
/// a bitmap allows, because a bitmap has no parts - there is no arm to raise
/// and no hand to put on a keyboard, so "thinking" and "replying" could only
/// ever be the same bob at two speeds. It read as a sticker being jiggled.
///
/// This is the same character as the renders in assets/agents, rebuilt as a
/// rig: body, face, eyes, brows, mouth, two arms, two feet, and props. Each
/// part is positioned by [_Rig], so a pose is a set of numbers and the
/// character can type at a laptop, lean into a thought, or toss a ball around
/// while it waits.
///
/// Drawn rather than shipped as frames for three reasons: it stays sharp at
/// 26px in a message row and at 128px on the empty state, it recolours itself
/// per agent from one accent, and a sprite sheet long enough not to loop
/// visibly would be several megabytes of the download.
enum OmCharacterPose {
  /// Sitting there, breathing, blinking. The resting state.
  idle,

  /// The turn has gone and nothing has come back. Leans into it, looks up and
  /// away, raises a hand, and gets a cloud of dots.
  thinking,

  /// Tokens are arriving, so the character is at a laptop typing them. The
  /// literal thing the coach is doing, which is why this reads as progress in
  /// a way a spinner does not.
  typing,

  /// Head down, working. Faster hands than [typing] and a furrowed brow, for
  /// a focus session rather than a reply.
  working,

  /// Off the clock: tossing something up and catching it.
  playing,
}

/// The character's colours, derived from one accent so a new agent needs no
/// new artwork.
@immutable
class OmCharacterPalette {
  const OmCharacterPalette({
    required this.body,
    required this.shade,
    required this.face,
    required this.ink,
    required this.blush,
    this.tuft,
  });

  /// The main coat.
  final Color body;

  /// Feet and arms, a touch deeper than the coat so they read as in front.
  final Color shade;

  /// The pale patch the face sits on.
  final Color face;

  /// Eyes, brows, mouth.
  final Color ink;

  /// The cheeks.
  final Color blush;

  /// The swept quiff. Null for the agents that do not have one.
  final Color? tuft;

  @override
  bool operator ==(Object other) =>
      other is OmCharacterPalette &&
      other.body == body &&
      other.shade == shade &&
      other.face == face &&
      other.ink == ink &&
      other.blush == blush &&
      other.tuft == tuft;

  @override
  int get hashCode => Object.hash(body, shade, face, ink, blush, tuft);

  /// Pulled off a single accent, in the proportions the three renders use.
  factory OmCharacterPalette.from(Color accent, {bool quiff = false}) {
    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    const white = Color(0xFFFFFFFF);
    const deep = Color(0xFF2E2350);
    return OmCharacterPalette(
      body: mix(accent, white, 0.34),
      shade: mix(accent, deep, 0.10),
      face: mix(accent, white, 0.88),
      ink: mix(accent, deep, 0.58),
      blush: mix(accent, const Color(0xFFFF8FA0), 0.45),
      tuft: quiff ? mix(accent, const Color(0xFFFFD9A8), 0.72) : null,
    );
  }
}

/// The character, animated.
///
/// One controller, running continuously and never restarted. Every pose reads
/// its own rhythm off that single clock, because stopping a controller to
/// start another is what produces the jolt where a character snaps back to
/// rest between animations. A second controller handles only the crossfade
/// from the previous pose to the new one, so a change of pose is a half-second
/// move rather than a cut.
class OmCharacter extends StatefulWidget {
  const OmCharacter({
    super.key,
    required this.size,
    required this.palette,
    this.pose = OmCharacterPose.idle,
    this.restingEyes = OmCharacterEyes.open,
    this.restingMouth = OmCharacterMouth.smile,
    this.seed = 0,
    this.animate = true,
    this.showThought = true,
  });

  final double size;
  final OmCharacterPalette palette;
  final OmCharacterPose pose;

  /// How this character's face sits when nothing is happening. The three
  /// shipped agents differ exactly here: one beams, one keeps its eyes closed,
  /// one is a bit worried.
  final OmCharacterEyes restingEyes;
  final OmCharacterMouth restingMouth;

  /// Offsets the blink and sway, so a row of characters is not a chorus line.
  final int seed;

  /// False under reduce-motion: the character is drawn in its pose and holds
  /// still. The pose still changes, so it is never less informative.
  final bool animate;

  /// The thought cloud while thinking. Turned off where a larger one is
  /// already drawn over the avatar, so the screen does not show two.
  final bool showThought;

  @override
  State<OmCharacter> createState() => _OmCharacterState();
}

/// The resting eye shape.
enum OmCharacterEyes { open, closed, worried }

/// The resting mouth shape.
enum OmCharacterMouth { smile, soft, frown }

class _OmCharacterState extends State<OmCharacter>
    with TickerProviderStateMixin {
  /// The heartbeat. Long, so each pose can divide it down to its own rate
  /// without any of them needing a controller of their own.
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  /// Pose crossfade. 0 means "showing [_from]", 1 means "showing the widget's
  /// current pose".
  late final AnimationController _blend = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  late OmCharacterPose _from = widget.pose;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _clock.repeat();
  }

  @override
  void didUpdateWidget(covariant OmCharacter old) {
    super.didUpdateWidget(old);

    if (widget.animate != old.animate) {
      widget.animate ? _clock.repeat() : _clock.stop();
    }

    if (widget.pose != old.pose) {
      // Blend out of whatever is on screen right now, not out of the pose we
      // were nominally in. Changing pose twice inside the transition would
      // otherwise snap to the intermediate one.
      _from = old.pose;
      _blend
        ..value = 0
        ..forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _blend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_clock, _blend]),
        builder: (context, _) {
          final t = _clock.value;
          final k = Curves.easeInOutCubic.transform(_blend.value);
          final rig = _Rig.lerp(
            _rigFor(_from, t),
            _rigFor(widget.pose, t),
            k,
          );
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _CharacterPainter(
              rig: rig,
              palette: widget.palette,
              detail: widget.size >= 46,
              showThought: widget.showThought,
            ),
          );
        },
      ),
    );
  }

  _Rig _rigFor(OmCharacterPose pose, double t) => _Rig.pose(
        pose,
        t,
        seed: widget.seed,
        eyes: widget.restingEyes,
        mouth: widget.restingMouth,
        still: !widget.animate,
      );
}

/// Every number the painter needs, for one frame.
///
/// A value class rather than a pile of arguments so two poses can be
/// interpolated: [lerp] is what makes a pose change a movement instead of a
/// cut, and it is the whole reason the rig is separated from the drawing.
@immutable
class _Rig {
  const _Rig({
    required this.bob,
    required this.squash,
    required this.lean,
    required this.headTilt,
    required this.armL,
    required this.armR,
    required this.pupil,
    required this.lid,
    required this.brow,
    required this.mouthCurve,
    required this.mouthOpen,
    required this.laptop,
    required this.ball,
    required this.ballAt,
    required this.dots,
    required this.dotPhase,
  });

  /// Vertical travel of the whole body, in design units (the canvas is 100
  /// units wide), negative being up.
  final double bob;

  /// Breathing. Positive widens and flattens, which is what a body does on an
  /// in-breath; scaling both axes together just makes it loom.
  final double squash;

  /// Forward tip, in radians, pivoting at the feet.
  final double lean;

  /// Head tilt, in radians. Separate from [lean] so the character can tip its
  /// head without leaning its body.
  final double headTilt;

  /// Each arm: position of the paw and the angle of the paddle.
  final _Arm armL;
  final _Arm armR;

  /// Where the eyes are looking, in design units from centre.
  final Offset pupil;

  /// 0 fully open, 1 fully shut.
  final double lid;

  /// Brow position. Positive raises (surprise), negative furrows (effort).
  final double brow;

  /// +1 a smile, -1 a frown.
  final double mouthCurve;

  /// 0 closed, 1 wide.
  final double mouthOpen;

  /// Presence of each prop, 0 to 1. Faded rather than switched, so a laptop
  /// does not appear out of nothing mid-sentence.
  final double laptop;
  final double ball;

  /// Where the ball is, in design units, while it is being tossed.
  final Offset ballAt;

  final double dots;
  final double dotPhase;

  static _Rig lerp(_Rig a, _Rig b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    double d(double x, double y) => lerpDouble(x, y, t)!;
    return _Rig(
      bob: d(a.bob, b.bob),
      squash: d(a.squash, b.squash),
      lean: d(a.lean, b.lean),
      headTilt: d(a.headTilt, b.headTilt),
      armL: _Arm.lerp(a.armL, b.armL, t),
      armR: _Arm.lerp(a.armR, b.armR, t),
      pupil: Offset.lerp(a.pupil, b.pupil, t)!,
      lid: d(a.lid, b.lid),
      brow: d(a.brow, b.brow),
      mouthCurve: d(a.mouthCurve, b.mouthCurve),
      mouthOpen: d(a.mouthOpen, b.mouthOpen),
      laptop: d(a.laptop, b.laptop),
      ball: d(a.ball, b.ball),
      ballAt: Offset.lerp(a.ballAt, b.ballAt, t)!,
      dots: d(a.dots, b.dots),
      // Not interpolated: the dots' phase is an angle, and lerping it would
      // run the wave backwards through the transition.
      dotPhase: b.dots >= a.dots ? b.dotPhase : a.dotPhase,
    );
  }

  /// Where the arms rest when a pose has nothing for them to do.
  static const _armRestL = _Arm(Offset(22.5, 69), -0.30);
  static const _armRestR = _Arm(Offset(77.5, 69), 0.30);

  /// Builds the rig for [pose] at clock position [t].
  factory _Rig.pose(
    OmCharacterPose pose,
    double t, {
    required int seed,
    required OmCharacterEyes eyes,
    required OmCharacterMouth mouth,
    required bool still,
  }) {
    // Held at the top of the cycle under reduce-motion, so the pose is still
    // legible - hands on the keyboard, hand to the chin - with nothing moving.
    final clock = still ? 0.25 : t;
    final phase = (seed % 7) / 7;
    const tau = 2 * math.pi;

    double wave(double rate, [double offset = 0]) =>
        math.sin((clock * rate + offset + phase) * tau);

    final restLid = switch (eyes) {
      OmCharacterEyes.closed => 1.0,
      _ => 0.0,
    };
    final restBrow = switch (eyes) {
      OmCharacterEyes.worried => 0.55,
      _ => 0.0,
    };
    final restCurve = switch (mouth) {
      OmCharacterMouth.smile => 1.0,
      OmCharacterMouth.soft => 0.45,
      OmCharacterMouth.frown => -0.8,
    };

    // A blink: shut for about a tenth of the cycle, once per cycle, at a
    // moment that depends on the seed. Skipped entirely for an agent whose
    // eyes are closed anyway.
    double blink() {
      if (restLid == 1 || still) return restLid;
      final at = ((clock + phase) % 1.0);
      const start = 0.82, span = 0.07;
      if (at < start || at > start + span) return restLid;
      final u = (at - start) / span;
      return math.sin(u * math.pi);
    }

    switch (pose) {
      case OmCharacterPose.idle:
        // One slow breath, and a bob a beat behind it so the two never peak
        // together and read as a single pulse.
        return _Rig(
          bob: -0.9 * wave(1, 0.22),
          squash: 0.016 * wave(1),
          lean: 0.010 * wave(0.5),
          headTilt: 0.020 * wave(0.5, 0.3),
          armL: _armRestL.nudge(dy: 0.5 * wave(1, 0.1)),
          armR: _armRestR.nudge(dy: 0.5 * wave(1, 0.35)),
          pupil: Offset(0.55 * wave(0.25), 0.25 * wave(0.5)),
          lid: blink(),
          brow: restBrow,
          mouthCurve: restCurve,
          mouthOpen: mouth == OmCharacterMouth.smile ? 0.35 : 0.0,
          laptop: 0,
          ball: 0,
          ballAt: const Offset(50, 60),
          dots: 0,
          dotPhase: 0,
        );

      case OmCharacterPose.thinking:
        // Looking up and away, one paw at the chin, rocking slowly. The tell
        // is the held pause: a thought is not a vibration, so the body barely
        // moves while the dots do the work.
        final rock = wave(0.75);
        return _Rig(
          bob: -0.7 * wave(0.75, 0.2),
          squash: 0.012 * wave(0.75),
          lean: 0.02 + 0.012 * rock,
          headTilt: -0.13 + 0.028 * rock,
          armL: _armRestL.nudge(dx: 1.0, dy: -0.5),
          // Up under the jaw, which is the whole read of the pose.
          armR: _Arm(Offset(66.5 + 0.6 * rock, 57.5 + 0.8 * rock), -1.28),
          pupil: Offset(-1.5 + 0.5 * rock, -1.6),
          lid: 0.30 * restLid + 0.22,
          brow: restBrow * 0.5 + 0.30,
          mouthCurve: restCurve * 0.25,
          mouthOpen: 0.08,
          laptop: 0,
          ball: 0,
          ballAt: const Offset(50, 60),
          dots: 1,
          dotPhase: clock,
        );

      case OmCharacterPose.typing:
      case OmCharacterPose.working:
        // Hands on the keys, alternating. Half a cycle apart, and clamped to
        // the downstroke only, because a finger that rises as far as it falls
        // reads as waving rather than typing.
        final hard = pose == OmCharacterPose.working;
        final rate = hard ? 9.0 : 6.0;
        double tap(double offset) =>
            -1.5 * math.max(0.0, math.sin((clock * rate + offset) * tau));
        return _Rig(
          bob: -0.35 * wave(rate / 3),
          squash: 0.008 * wave(rate / 3),
          lean: hard ? 0.085 : 0.055,
          headTilt: (hard ? -0.02 : 0.01) + 0.012 * wave(rate / 6),
          armL: _Arm(Offset(38, 74 + tap(0)), 0.42),
          armR: _Arm(Offset(62, 74 + tap(0.5)), -0.42),
          // Eyes down on the screen, tracking across it as if reading back.
          pupil: Offset(0.9 * wave(rate / 6), 1.9),
          lid: math.max(blink(), hard ? 0.26 : 0.16),
          brow: hard ? -0.6 : restBrow * 0.4 - 0.15,
          mouthCurve: hard ? -0.1 : restCurve * 0.3,
          mouthOpen: 0.05,
          laptop: 1,
          ball: 0,
          ballAt: const Offset(50, 60),
          dots: 0,
          dotPhase: 0,
        );

      case OmCharacterPose.playing:
        // A ball tossed and caught. The arc is a parabola rather than a sine,
        // because a thrown thing hangs at the top and falls fast, and a sine
        // does the opposite of that.
        final u = (clock * 2) % 1.0;
        final rise = 4 * u * (1 - u);
        final ballY = 66 - 54 * rise;
        final ballX = 50 + 7.0 * math.sin(u * math.pi * 2);
        // Hands are up at the catch and the throw, down while it is in the air.
        final reach = math.max(0.0, 1 - rise * 2.1);
        return _Rig(
          bob: -1.6 * rise,
          squash: -0.03 * (1 - rise) + 0.02,
          lean: -0.02 * rise,
          headTilt: 0.05 * math.sin(u * math.pi * 2),
          armL: _Arm(
            Offset(33 - 2 * reach, 66 - 7 * reach),
            -0.75 - 0.5 * reach,
          ),
          armR: _Arm(
            Offset(67 + 2 * reach, 66 - 7 * reach),
            0.75 + 0.5 * reach,
          ),
          // Watching the ball, which is the thing that sells it as play rather
          // than as arm-waving.
          pupil: Offset((ballX - 50) * 0.18, (ballY - 48) * 0.07),
          lid: math.min(blink(), 0.4),
          brow: 0.35,
          mouthCurve: 1,
          mouthOpen: 0.5,
          laptop: 0,
          ball: 1,
          ballAt: Offset(ballX, ballY),
          dots: 0,
          dotPhase: 0,
        );
    }
  }
}

/// One arm: where the paw is, and which way the paddle points.
@immutable
class _Arm {
  const _Arm(this.at, this.angle);

  final Offset at;
  final double angle;

  _Arm nudge({double dx = 0, double dy = 0}) =>
      _Arm(at.translate(dx, dy), angle);

  static _Arm lerp(_Arm a, _Arm b, double t) =>
      _Arm(Offset.lerp(a.at, b.at, t)!, lerpDouble(a.angle, b.angle, t)!);
}

/// The paints whose shaders cover a fixed rectangle, built once per palette.
///
/// Every one of these used to be constructed inside paint, so a character
/// allocated about ten gradient shaders per frame - sixty times a second,
/// times every character on screen. The geometry they cover does not move
/// (the canvas transform does the moving), so they only ever had to be built
/// once. Keyed by palette, of which there are three.
class _Brushes {
  _Brushes(this.p);

  final OmCharacterPalette p;

  static final Map<OmCharacterPalette, _Brushes> _cache = {};
  static _Brushes of(OmCharacterPalette p) =>
      _cache.putIfAbsent(p, () => _Brushes(p));

  static const _footRect =
      Rect.fromLTRB(-8.5, -7.75, 8.5, 7.75);
  static const _armRect = Rect.fromLTRB(-10.5, -7, 10.5, 7);
  static const _patchRect = Rect.fromLTRB(28, 22, 72, 60);

  late final Paint body = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.35, -0.55),
      radius: 1.15,
      colors: [
        Color.lerp(p.body, Colors.white, 0.26)!,
        p.body,
        Color.lerp(p.body, p.shade, 0.5)!,
      ],
      stops: const [0, 0.58, 1],
    ).createShader(_CharacterPainter._body_.getBounds());

  late final Paint foot = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.3, -0.5),
      colors: [
        Color.lerp(p.body, Colors.white, 0.10)!,
        Color.lerp(p.body, p.shade, 0.75)!,
      ],
    ).createShader(_footRect);

  late final Paint arm = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.35, -0.55),
      colors: [
        Color.lerp(p.body, Colors.white, 0.12)!,
        Color.lerp(p.body, p.shade, 0.8)!,
      ],
    ).createShader(_armRect);

  late final Paint patch = Paint()
    ..shader = RadialGradient(
      colors: [
        p.face.withValues(alpha: 0.88),
        p.face.withValues(alpha: 0.80),
        p.face.withValues(alpha: 0),
      ],
      stops: const [0, 0.40, 0.98],
    ).createShader(_patchRect);

  late final List<(Rect, Paint)> blush = [
    for (final dx in [-16.0, 16.0])
      () {
        final r = Rect.fromCenter(
            center: Offset(50 + dx, 46.5), width: 16, height: 11);
        return (
          r,
          Paint()
            ..shader = RadialGradient(
              colors: [
                p.blush.withValues(alpha: 0.42),
                p.blush.withValues(alpha: 0),
              ],
              stops: const [0.25, 1],
            ).createShader(r),
        );
      }(),
  ];

  late final List<Paint> halo = [
    for (final (w, a) in const [(3.4, 0.16), (2.4, 0.3), (1.5, 0.55)])
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color =
            Color.lerp(p.body, Colors.white, 0.10)!.withValues(alpha: a),
  ];

  late final Paint hair = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.62
    ..strokeCap = StrokeCap.round
    ..color =
        Color.lerp(p.body, Colors.white, 0.18)!.withValues(alpha: 0.5);

  late final Paint ink = Paint()..color = p.ink;
}

/// Draws the rig.
///
/// Works in a fixed 100x100 design space and scales once at the top, so every
/// measurement below is a plain number that means the same thing at 26px and
/// at 128px.
class _CharacterPainter extends CustomPainter {
  _CharacterPainter({
    required this.rig,
    required this.palette,
    required this.detail,
    required this.showThought,
  });

  final _Rig rig;
  final OmCharacterPalette palette;
  final bool showThought;

  /// The fixed-geometry paints for this palette, built once and shared.
  late final _Brushes brush = _Brushes.of(palette);

  /// Off below about 46px, where the fur fringe turns to mud and a laptop is
  /// four grey pixels. The body and the motion survive; the garnish does not.
  final bool detail;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    _ground(canvas);

    // Everything above the floor leans and bobs together, pivoting where the
    // feet meet the ground rather than at the centre, so a lean looks like
    // leaning and not like sliding.
    canvas.save();
    canvas.translate(50, 92);
    canvas.rotate(rig.lean);
    canvas.translate(-50, -92 + rig.bob);

    if (rig.ball > 0.01) _ballShadow(canvas);

    // Squash is applied to the body alone. Stretching the feet with it is what
    // makes a breathing character look like it is made of rubber.
    canvas.save();
    canvas.translate(50, 92);
    canvas.scale(1 + rig.squash, 1 - rig.squash);
    canvas.translate(-50, -92);
    _body(canvas);
    _face(canvas);
    canvas.restore();

    // In front of the body, in the order they overlap on the renders: feet
    // peek out from under the belly, arms rest on top of it, and the laptop
    // is nearer the viewer than either.
    _feet(canvas);
    _arms(canvas);
    if (rig.laptop > 0.01 && detail) _laptop(canvas);
    if (rig.ball > 0.01) _ball(canvas);

    canvas.restore();

    if (rig.dots > 0.01 && detail && showThought) _dots(canvas);

    canvas.restore();
  }

  // The silhouette: an egg, wider and heavier at the bottom. Built once: it
  // is the same shape every frame, and the squash is applied by the canvas.
  static final Path _body_ = Path()
    ..moveTo(50, 11)
    ..cubicTo(68, 11, 84, 38, 84, 60)
    ..cubicTo(84, 80, 70, 91, 50, 91)
    ..cubicTo(30, 91, 16, 80, 16, 60)
    ..cubicTo(16, 38, 32, 11, 50, 11)
    ..close();

  static final Path _footPath = Path()
    ..addOval(Rect.fromCenter(
        center: Offset.zero, width: 17, height: 15.5));

  static final Path _armPath = Path()
    ..addOval(
        Rect.fromCenter(center: Offset.zero, width: 21, height: 14));

  static final Path _quiffPath = Path()
    ..moveTo(52, 13)
    ..cubicTo(64, 7, 80, 12, 83, 24)
    ..cubicTo(85, 34, 78, 40, 71, 37)
    ..cubicTo(74, 28, 68, 19, 52, 20)
    ..close();

  /// Every hair for a given outline, as one path, worked out once.
  ///
  /// This used to walk the outline with PathMetrics and issue 150 drawLine
  /// calls on every paint, for every part, for every character on screen.
  /// The outlines are constant, so all of that was recomputed sixty times a
  /// second to produce the same picture: it took the test suite from forty
  /// seconds to over ten minutes, which is a fair proxy for what it was doing
  /// to a phone. Now it is one cached path and one draw call.
  static final Map<Object, Path> _furCache = {};

  static Path _furFor(Object id, Path outline, int count, double len) =>
      _furCache.putIfAbsent(id, () {
        final hairs = Path();
        final metric = outline.computeMetrics().first;
        final total = metric.length;
        for (var i = 0; i < count; i++) {
          final tan = metric.getTangentForOffset(total * i / count);
          if (tan == null) continue;
          // The outward normal is the tangent turned a quarter turn.
          final n = Offset(tan.vector.dy, -tan.vector.dx);
          final l = len * (0.55 + 0.45 * math.sin(i * 2.399));
          // Leaned along the surface, because fur lies down; straight out is
          // what made the first version look like a cog.
          final lean = Offset(tan.vector.dx, tan.vector.dy) * (l * 0.45);
          final a = tan.position - n * 0.7;
          final b = tan.position + n * l + lean;
          hairs
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy);
        }
        return hairs;
      });

  void _ground(Canvas canvas) {
    // Tied to the bob, so the character reads as leaving the floor rather than
    // as the floor following it up.
    final lift = (-rig.bob).clamp(0.0, 4.0) / 4.0;
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(50, 95.5),
        width: 46 - 6 * lift,
        height: 6 - 1.2 * lift,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.ink.withValues(alpha: 0.15 - 0.05 * lift),
            palette.ink.withValues(alpha: 0),
          ],
          stops: const [0.3, 1],
        ).createShader(Rect.fromCenter(
          center: const Offset(50, 95.5),
          width: 46 - 6 * lift,
          height: 6 - 1.2 * lift,
        )),
    );
  }

  void _feet(Canvas canvas) {
    for (final dx in [-8.5, 8.5]) {
      final c = Offset(50 + dx, 89.5);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.drawOval(_Brushes._footRect, brush.foot);
      if (detail) {
        _furEdge(canvas, _footPath, _furFor(#foot, _footPath, 26, 1.3));
      }
      canvas.restore();
    }
  }

  void _body(Canvas canvas) {
    final path = _body_;

    // Lit from above-left, the way all three renders are, so the drawn version
    // sits next to them without looking flat.
    canvas.drawPath(path, brush.body);

    if (detail) _furEdge(canvas, path, _furFor(#body, path, 150, 1.25));
    _quiff(canvas);
  }

  /// Ember's swept tuft. Drawn over the body's top right, curling up and out,
  /// which is the one thing that tells the three agents apart in silhouette.
  void _quiff(Canvas canvas) {
    final tuft = palette.tuft;
    if (tuft == null) return;

    final path = _quiffPath;

    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.2, -0.6),
          colors: [Color.lerp(tuft, Colors.white, 0.25)!, tuft],
        ).createShader(path.getBounds()),
    );

    // The cap of the same colour over the crown, so the tuft is part of the
    // coat rather than an ear stuck on the side.
    final cap = Path()
      ..moveTo(28, 30)
      ..cubicTo(33, 13, 44, 11, 54, 11)
      ..cubicTo(66, 11, 72, 19, 70, 31)
      ..cubicTo(58, 23, 40, 24, 28, 30)
      ..close();
    // Faded along its lower edge rather than filled flat, so the cap grows
    // out of the coat. A hard boundary here reads as a hat.
    canvas.drawPath(
      cap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tuft, tuft.withValues(alpha: 0)],
          stops: const [0.45, 1],
        ).createShader(cap.getBounds()),
    );
    if (detail) _furEdge(canvas, path, _furFor(#quiff, path, 34, 1.2));
  }

  /// The fuzzy edge.
  ///
  /// Two parts, because either alone looks wrong. A blurred stroke along the
  /// silhouette gives the soft halo that makes the shape read as a plush toy;
  /// the first version had only the strokes and the character came out looking
  /// like a cog. Short hairs on top of the halo give it texture, kept thin and
  /// dense so they read as fuzz at a glance rather than as spikes.
  ///
  /// Lengths vary by index rather than randomly, so the coat is the same coat
  /// every frame instead of crawling.
  void _furEdge(Canvas canvas, Path path, Path hairs) {
    // Three concentric strokes rather than one blurred one.
    //
    // MaskFilter.blur is the expensive call in this painter, and the painter
    // runs every frame for every character on screen - six blurs each, times
    // a picker grid of three, is a lot of work to produce a soft edge.
    // Feathering by hand costs three cheap strokes and is indistinguishable
    // at the sizes this is drawn.
    for (final paint in brush.halo) {
      canvas.drawPath(path, paint);
    }

    canvas.drawPath(hairs, brush.hair);
  }

  void _face(Canvas canvas) {
    canvas.save();
    // The face turns with the head, around a point behind it.
    canvas.translate(50, 54);
    canvas.rotate(rig.headTilt);
    canvas.translate(-50, -54);

    // The pale patch, faded at its edge rather than cut, which is how it looks
    // on the renders - the coat grows out of it.
    canvas.drawOval(_Brushes._patchRect, brush.patch);

    if (detail) {
      // A radial falloff, not a blurred oval: same soft cheek, no filter.
      for (final (r, paint) in brush.blush) {
        canvas.drawOval(r, paint);
      }
    }

    _eyes(canvas);
    _mouth(canvas);
    canvas.restore();
  }

  void _eyes(Canvas canvas) {
    final ink = brush.ink;
    const open = 9.4;
    final h = open * (1 - rig.lid);

    for (final dx in [-8.5, 8.5]) {
      final c = Offset(50 + dx, 39);

      if (h < 2.2) {
        // Shut. A downward arc, which is also the resting face of the agent
        // that keeps its eyes closed, so a blink lands on the same shape.
        final p = Path()
          ..moveTo(c.dx - 4.4, c.dy)
          ..quadraticBezierTo(c.dx, c.dy + 3.4, c.dx + 4.4, c.dy);
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.9
            ..strokeCap = StrokeCap.round
            ..color = palette.ink,
        );
        continue;
      }

      canvas.save();
      canvas.clipRect(Rect.fromCenter(
          center: c, width: 12, height: math.max(h, 0.1)));
      canvas.drawOval(
        Rect.fromCenter(
          center: c + Offset(rig.pupil.dx, rig.pupil.dy),
          width: 7.4,
          height: open,
        ),
        ink,
      );
      // The catchlight. Fixed to the upper left of the eye rather than to the
      // pupil, because it is a reflection of the light, not part of the eye.
      canvas.drawCircle(
        c + Offset(rig.pupil.dx - 1.6, rig.pupil.dy - 2.4),
        1.45,
        Paint()..color = Colors.white.withValues(alpha: 0.92),
      );
      canvas.restore();
    }

    if (rig.brow.abs() > 0.02) _brows(canvas);
  }

  void _brows(Canvas canvas) {
    // Positive lifts the inner ends into a worried peak; negative drives them
    // down into a furrow. One number, two readable expressions - and the sign
    // matters more than it looks: inner ends *down* is the universal angry
    // brow, so getting it backwards made the gentlest agent look cross.
    final b = rig.brow;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = palette.ink.withValues(alpha: 0.9);

    for (final side in [-1.0, 1.0]) {
      final x = 50 + side * 8.5;
      final y = 30.6 - 1.4 * b.clamp(0.0, 1.0) + 2.6 * (-b).clamp(0.0, 1.0);
      final inner = Offset(x - side * 4.2, y - 2.1 * b);
      final outer = Offset(x + side * 4.2, y + 0.9 * b);
      canvas.drawPath(
        Path()
          ..moveTo(inner.dx, inner.dy)
          ..quadraticBezierTo(x, y - 1.5 - 0.6 * b, outer.dx, outer.dy),
        paint,
      );
    }
  }

  void _mouth(Canvas canvas) {
    const c = Offset(50, 50.5);
    final w = 7.0 + 2.5 * rig.mouthOpen;
    final curve = rig.mouthCurve;

    if (rig.mouthOpen > 0.18) {
      // Open: a filled shape with a tongue, which is what makes the smile read
      // as a laugh rather than as a line.
      final h = 3.0 + 5.0 * rig.mouthOpen;
      final mouth = Path()
        ..moveTo(c.dx - w / 2, c.dy - h * 0.18)
        ..quadraticBezierTo(c.dx, c.dy - h * 0.18 - 2.2 * curve,
            c.dx + w / 2, c.dy - h * 0.18)
        ..quadraticBezierTo(c.dx + w * 0.42, c.dy + h * 0.82, c.dx,
            c.dy + h * 0.82)
        ..quadraticBezierTo(c.dx - w * 0.42, c.dy + h * 0.82, c.dx - w / 2,
            c.dy - h * 0.18)
        ..close();
      canvas.drawPath(mouth, Paint()..color = palette.ink);
      canvas.save();
      canvas.clipPath(mouth);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(c.dx, c.dy + h * 0.72), width: w * 0.8, height: h),
        Paint()..color = palette.blush,
      );
      canvas.restore();
      return;
    }

    canvas.drawPath(
      Path()
        ..moveTo(c.dx - w / 2, c.dy)
        ..quadraticBezierTo(c.dx, c.dy + 3.2 * curve, c.dx + w / 2, c.dy),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..color = palette.ink,
    );
  }

  void _arms(Canvas canvas) {
    for (final arm in [rig.armL, rig.armR]) {
      canvas.save();
      canvas.translate(arm.at.dx, arm.at.dy);
      canvas.rotate(arm.angle);
      // Lit like the body rather than filled flat: a solid dark oval reads as
      // a sticker on the front, which is what the first pass looked like.
      canvas.drawOval(_Brushes._armRect, brush.arm);
      if (detail) _furEdge(canvas, _armPath, _furFor(#arm, _armPath, 30, 1.25));
      canvas.restore();
    }
  }

  /// The laptop, from the user's side of the table.
  ///
  /// Drawn in the only arrangement that reads at this size: a short screen
  /// standing behind, a keyboard deck in perspective in front of it, and the
  /// paws coming down onto the deck. The screen is deliberately low, because
  /// a correctly proportioned one hides the character behind it and then the
  /// pose is a laptop with a head on top.
  void _laptop(Canvas canvas) {
    final a = rig.laptop;
    final shell = palette.ink.withValues(alpha: 0.9 * a);
    final glow = Color.lerp(palette.face, palette.body, 0.22)!
        .withValues(alpha: 0.95 * a);

    // Screen, behind the deck.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(31, 58.5, 38, 15),
        const Radius.circular(2),
      ),
      Paint()..color = shell,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(32.6, 60, 34.8, 12),
        const Radius.circular(1.2),
      ),
      Paint()..color = glow,
    );

    // Deck, splaying towards the viewer.
    final deck = Path()
      ..moveTo(31, 73.5)
      ..lineTo(69, 73.5)
      ..lineTo(77, 81.5)
      ..lineTo(23, 81.5)
      ..close();
    canvas.drawPath(deck, Paint()..color = shell);

    // Keys, as two bands rather than individual caps: at 26px the caps are
    // noise, and at 128px two bands still say keyboard.
    final keys = Paint()
      ..color = Color.lerp(palette.face, palette.ink, 0.35)!
          .withValues(alpha: 0.55 * a);
    canvas.drawPath(
      Path()
        ..moveTo(34, 75.5)
        ..lineTo(66, 75.5)
        ..lineTo(68.6, 78)
        ..lineTo(31.4, 78)
        ..close(),
      keys,
    );
    canvas.drawPath(
      Path()
        ..moveTo(39, 79)
        ..lineTo(61, 79)
        ..lineTo(63, 80.6)
        ..lineTo(37, 80.6)
        ..close(),
      keys,
    );
  }

  void _ballShadow(Canvas canvas) {
    final height = (66 - rig.ballAt.dy).clamp(0.0, 54.0) / 54.0;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rig.ballAt.dx, 93),
        width: 11 - 3.5 * height,
        height: 3.2 - 1.1 * height,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.ink
                .withValues(alpha: (0.2 - 0.1 * height) * rig.ball),
            palette.ink.withValues(alpha: 0),
          ],
          stops: const [0.3, 1],
        ).createShader(Rect.fromCenter(
          center: Offset(rig.ballAt.dx, 93),
          width: 11 - 3.5 * height,
          height: 3.2 - 1.1 * height,
        )),
    );
  }

  void _ball(Canvas canvas) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.4, -0.5),
        colors: [
          Color.lerp(palette.blush, Colors.white, 0.45)!,
          palette.blush,
        ],
      ).createShader(Rect.fromCircle(center: rig.ballAt, radius: 6));
    canvas.drawCircle(rig.ballAt, 6.5 * rig.ball, paint);
  }

  void _dots(Canvas canvas) {
    // A thought cloud, up and to the side of the head it belongs to.
    const anchor = Offset(76, 16);
    final a = rig.dots;

    canvas.drawCircle(const Offset(68, 26), 2.4 * a,
        Paint()..color = palette.face.withValues(alpha: 0.95 * a));
    canvas.drawCircle(const Offset(72.5, 21.5), 3.4 * a,
        Paint()..color = palette.face.withValues(alpha: 0.95 * a));
    canvas.drawCircle(anchor, 11 * a,
        Paint()..color = palette.face.withValues(alpha: 0.97 * a));

    for (var i = 0; i < 3; i++) {
      // A third of a cycle apart, so they rise as a wave and not in unison.
      final u = math.max(
          0.0, math.sin((rig.dotPhase * 3 - i / 3) * 2 * math.pi));
      canvas.drawCircle(
        Offset(anchor.dx - 5 + i * 5, anchor.dy - 1.6 * u),
        1.7 * a,
        Paint()..color = palette.ink.withValues(alpha: (0.45 + 0.5 * u) * a),
      );
    }
  }

  @override
  bool shouldRepaint(_CharacterPainter old) =>
      old.rig != rig ||
      old.palette != palette ||
      old.detail != detail ||
      old.showThought != showThought;
}
