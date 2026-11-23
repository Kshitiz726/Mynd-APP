import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent.dart';
import '../providers/settings_provider.dart';
import 'om_character.dart';

/// What the avatar is doing, which is the only thing that drives its motion.
enum AgentMood {
  /// Sitting there. Breathing, blinking, and not much else.
  idle,

  /// The turn has been sent and nothing has come back yet.
  thinking,

  /// Tokens are arriving, so the character is at a laptop putting them there.
  speaking,

  /// Head down on something that is not a reply: a focus session, a job
  /// running in the background.
  working,

  /// Nothing to do, and visibly enjoying it.
  playing,
}

/// The agent's face, alive.
///
/// This used to be `Image.asset` with a transform on it. A bitmap has no
/// parts, so the only motion available was sliding and scaling the whole
/// picture - which is why "thinking" and "replying" were the same bob at two
/// speeds, and why it read as a sticker being jiggled rather than as a
/// character. [OmCharacter] draws the same creature as a rig with a body,
/// arms, eyes and props, so it can actually sit at a laptop and type.
///
/// The PNGs in assets/agents are still the source of truth for what each
/// agent looks like; this is that design rebuilt in paths, recoloured from
/// each agent's accent.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({
    super.key,
    required this.agent,
    required this.size,
    this.mood = AgentMood.idle,
    this.showRing = true,
    this.showThought = true,
    this.emotion,
    this.onTap,
  });

  final Agent agent;
  final double size;
  final AgentMood mood;

  /// The accent ring. Off in dense places like a picker grid, where a dozen
  /// rings is noise.
  final bool showRing;

  /// The character's own thought cloud while it is thinking. Off where a
  /// bigger one is already being drawn over the top, so there are not two.
  final bool showThought;

  /// Overrides the face this agent rests in. Null uses how the agent ships,
  /// which is what every screen wants except the one where you are changing
  /// it and watching the preview.
  final AgentEmotion? emotion;

  final VoidCallback? onTap;

  /// The three shipped faces, reproduced from the agent's mood rather than
  /// hardcoded per id, so a tuned agent actually looks like the mood it is in.
  static (OmCharacterEyes, OmCharacterMouth) _faceFor(AgentEmotion e) =>
      switch (e) {
        AgentEmotion.calm =>
          (OmCharacterEyes.closed, OmCharacterMouth.soft),
        AgentEmotion.upbeat =>
          (OmCharacterEyes.open, OmCharacterMouth.smile),
        AgentEmotion.focused =>
          (OmCharacterEyes.open, OmCharacterMouth.soft),
        AgentEmotion.gentle =>
          (OmCharacterEyes.worried, OmCharacterMouth.frown),
        AgentEmotion.firedUp =>
          (OmCharacterEyes.open, OmCharacterMouth.smile),
      };

  @override
  Widget build(BuildContext context) {
    final a = agent;
    final s = size;
    final reduceMotion =
        context.select<SettingsProvider, bool>((x) => x.reduceMotion);

    final pose = switch (mood) {
      AgentMood.idle => OmCharacterPose.idle,
      AgentMood.thinking => OmCharacterPose.thinking,
      AgentMood.speaking => OmCharacterPose.typing,
      AgentMood.working => OmCharacterPose.working,
      AgentMood.playing => OmCharacterPose.playing,
    };

    final (eyes, mouth) = _faceFor(emotion ?? a.defaults.emotion);

    Widget out = SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (showRing)
            _Ring(colour: a.accent, mood: mood, animate: !reduceMotion),
          OmCharacter(
            size: s,
            // Ember is the one with the quiff; it is what tells the three
            // apart in silhouette.
            palette:
                OmCharacterPalette.from(a.accent, quiff: a.id == 'ember'),
            pose: pose,
            restingEyes: eyes,
            restingMouth: mouth,
            // So a picker grid is not a chorus line blinking in unison.
            seed: a.id.hashCode,
            animate: !reduceMotion,
            showThought: showThought,
          ),
        ],
      ),
    );

    if (onTap != null) {
      out = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: out,
      );
    }
    return Semantics(
      label: switch (mood) {
        AgentMood.idle => '${a.name}, your coach',
        AgentMood.thinking => '${a.name} is thinking',
        AgentMood.speaking => '${a.name} is replying',
        AgentMood.working => '${a.name} is working',
        AgentMood.playing => '${a.name}, your coach',
      },
      button: onTap != null,
      child: out,
    );
  }
}

/// The ring around the character.
///
/// Idle it is a faint static hairline; working, it is an arc that travels, so
/// there is a moving part even at the instant the character's own motion is at
/// the top or bottom of its travel and momentarily still.
class _Ring extends StatefulWidget {
  const _Ring({required this.colour, required this.mood, required this.animate});

  final Color colour;
  final AgentMood mood;
  final bool animate;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _Ring old) {
    super.didUpdateWidget(old);
    if (widget.animate != old.animate) {
      widget.animate ? _c.repeat() : _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _RingPainter(
            colour: widget.colour,
            t: _c.value,
            busy: widget.mood == AgentMood.thinking ||
                widget.mood == AgentMood.speaking ||
                widget.mood == AgentMood.working,
            fast: widget.mood == AgentMood.speaking,
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.colour,
    required this.t,
    required this.busy,
    required this.fast,
  });

  final Color colour;
  final double t;
  final bool busy;
  final bool fast;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      centre,
      r * 1.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.055
        ..color = colour.withValues(alpha: busy ? 0.22 : 0.16),
    );

    if (!busy) return;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r * 1.02),
      t * 2 * 3.1415926 * (fast ? 3.0 : 2.0),
      fast ? 0.88 : 1.57,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.075
        ..strokeCap = StrokeCap.round
        ..color = colour.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.busy != busy || old.fast != fast || old.colour != colour;
}
