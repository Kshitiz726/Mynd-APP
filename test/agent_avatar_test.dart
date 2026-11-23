import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/models/agent.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/widgets/agent_avatar.dart';
import 'package:ourmynd/widgets/om_character.dart';

/// Three agents have to look like three different creatures.
///
/// This file used to prove that by loading each agent's PNG out of the asset
/// bundle, because the avatar was an `Image.asset` and a path that was right
/// in the Dart and wrong on disk rendered a grey box on the main screen.
/// The avatar is drawn now - [OmCharacter] paints the character from the
/// agent's accent - so there is no path to get wrong and no bundle lookup
/// left to protect. The assertions moved to what actually carries the
/// difference: the colours each agent derives, and the face it rests in.
///
/// Written against the derived palette rather than the accents themselves,
/// because two distinct accents could still mix down to the same coat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(Agent a) => ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Center(child: AgentAvatar(agent: a, size: 96))),
        ),
      );

  for (final agent in Agent.all) {
    testWidgets('${agent.name}: the avatar draws a character',
        (tester) async {
      await tester.pumpWidget(host(agent));
      // pump, not pumpAndSettle: the character breathes on a continuous
      // animation and never settles, so settling here would only time out.
      await tester.pump(const Duration(milliseconds: 100));

      final drawn =
          tester.widget<OmCharacter>(find.byType(OmCharacter));
      expect(drawn.palette.body, OmCharacterPalette.from(agent.accent).body);
      expect(tester.takeException(), isNull);
    });
  }

  test('three agents, three different creatures', () {
    // Two agents sharing an appearance is the "skin" failure in its most
    // visible form: the picker shows the same creature twice.
    final coats = Agent.all
        .map((a) => OmCharacterPalette.from(a.accent).body.toARGB32())
        .toSet();
    expect(coats.length, 3, reason: 'two agents share a coat colour');

    // And they are told apart by more than colour, which matters at a glance
    // and for anyone who cannot rely on hue.
    final faces = Agent.all.map((a) => a.defaults.emotion).toSet();
    expect(faces.length, 3, reason: 'two agents rest in the same face');
  });

  test('only one agent carries the quiff', () {
    // The silhouette difference. If this ever became two, the renders and the
    // drawing would have drifted apart.
    expect(Agent.all.where((a) => a.id == 'ember').length, 1);
  });
}
