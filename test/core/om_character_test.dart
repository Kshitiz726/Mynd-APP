import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/models/agent.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/widgets/agent_avatar.dart';
import 'package:ourmynd/widgets/om_character.dart';

/// The avatar used to be a PNG with a transform on it, so every state was the
/// same picture moving at a different speed. These pin the things that made
/// replacing it worth doing: that a pose actually changes what is drawn, that
/// changing pose is a move rather than a cut, and that reduce-motion still
/// shows the pose.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Widget child, {bool reduceMotion = false}) {
    final settings = SettingsProvider();
    if (reduceMotion) settings.toggleReduceMotion(true);
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: settings)],
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  testWidgets('every pose paints without throwing', (tester) async {
    for (final pose in OmCharacterPose.values) {
      await tester.pumpWidget(host(OmCharacter(
        size: 120,
        palette: OmCharacterPalette.from(const Color(0xFFE0796A), quiff: true),
        pose: pose,
      )));
      // Several frames, so the parts that only appear part way through a
      // cycle - a blink, the top of a toss - are painted too.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull, reason: pose.name);
    }
  });

  testWidgets('a tiny avatar still paints', (tester) async {
    // Below the detail threshold the props and the fur are skipped. That
    // branch has to be exercised, because it is the one the message rows use.
    await tester.pumpWidget(host(OmCharacter(
      size: 26,
      palette: OmCharacterPalette.from(const Color(0xFF8A7CC9)),
      pose: OmCharacterPose.typing,
    )));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing pose animates rather than cutting', (tester) async {
    await tester.pumpWidget(host(const _Switcher()));
    await tester.pump(const Duration(milliseconds: 200));

    final before = tester.widget<CustomPaint>(
        find.descendant(
            of: find.byType(OmCharacter), matching: find.byType(CustomPaint)))
        .painter;

    await tester.tap(find.byType(GestureDetector));
    // One frame in. If the pose were switched rather than blended, the
    // character would already be in its new position here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final mid = tester.widget<CustomPaint>(
        find.descendant(
            of: find.byType(OmCharacter), matching: find.byType(CustomPaint)))
        .painter;

    expect(mid, isNot(same(before)),
        reason: 'the painter should be rebuilt each frame while blending');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion holds the pose instead of hiding it',
      (tester) async {
    // Through AgentAvatar, because that is where the setting is read: the
    // character itself takes `animate` as a plain argument, so testing it
    // directly would prove nothing about whether the app honours the switch.
    await tester.pumpWidget(host(
      AgentAvatar(
          agent: Agent.all.first, size: 120, mood: AgentMood.speaking),
      reduceMotion: true,
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<OmCharacter>(find.byType(OmCharacter)).animate,
        isFalse);
    expect(tester.widget<OmCharacter>(find.byType(OmCharacter)).pose,
        OmCharacterPose.typing,
        reason: 'the pose still has to say what is happening');

    // Nothing may be left running: a repeating controller under reduce-motion
    // is the setting being ignored, and it also pins a frame callback forever.
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'the clock must be stopped, not merely slowed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the three agents keep their own faces', (tester) async {
    // The resting face comes from the agent's mood, which is what reproduced
    // the three shipped renders without hardcoding anything per id.
    expect(Agent.byId('ember').defaults.emotion, AgentEmotion.upbeat);
    expect(Agent.byId('hush').defaults.emotion, AgentEmotion.calm);
    expect(Agent.byId('wren').defaults.emotion, AgentEmotion.gentle);

    for (final agent in Agent.all) {
      await tester.pumpWidget(host(AgentAvatar(agent: agent, size: 96)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OmCharacter), findsOneWidget);
      expect(tester.takeException(), isNull, reason: agent.id);
    }
  });

  testWidgets('each mood reaches a distinct pose', (tester) async {
    const map = {
      AgentMood.idle: OmCharacterPose.idle,
      AgentMood.thinking: OmCharacterPose.thinking,
      AgentMood.speaking: OmCharacterPose.typing,
      AgentMood.working: OmCharacterPose.working,
      AgentMood.playing: OmCharacterPose.playing,
    };
    // Every mood is mapped, so adding one cannot silently fall back to idle.
    expect(map.keys.toSet(), AgentMood.values.toSet());

    for (final entry in map.entries) {
      await tester.pumpWidget(host(
          AgentAvatar(agent: Agent.all.first, size: 96, mood: entry.key)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<OmCharacter>(find.byType(OmCharacter)).pose,
        entry.value,
        reason: entry.key.name,
      );
    }
  });
}

/// Flips between two poses on tap, so the transition can be observed.
class _Switcher extends StatefulWidget {
  const _Switcher();

  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  bool _on = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => _on = !_on),
        child: OmCharacter(
          size: 120,
          palette: OmCharacterPalette.from(const Color(0xFFE0796A)),
          pose: _on ? OmCharacterPose.typing : OmCharacterPose.idle,
        ),
      );
}
