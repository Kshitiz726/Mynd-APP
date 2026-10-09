import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/models/agent.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/widgets/agent_avatar.dart';

/// The roster names three asset paths. A path that is right in the Dart and
/// wrong on disk compiles, passes every test that only reads the string, and
/// then renders a grey box on the one screen the app is built around - so the
/// picture is loaded here from the real bundle rather than asserted as text.
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
    test('${agent.name}: the file is really in the bundle', () async {
      // The bundle, not the filesystem: an asset present on disk but outside
      // the pubspec globs is exactly the mistake this is here to catch, and a
      // File() check would pass straight through it.
      final bytes = await rootBundle.load(agent.asset);
      expect(bytes.lengthInBytes, greaterThan(1000),
          reason: '${agent.asset} is missing or empty in the asset bundle');
    });

    testWidgets('${agent.name}: the avatar points at its own file',
        (tester) async {
      await tester.pumpWidget(host(agent));
      // pump, not pumpAndSettle: the avatar breathes on a continuous animation
      // and never settles, so settling here would only ever time out.
      await tester.pump(const Duration(milliseconds: 100));

      final image = tester.widget<Image>(find.descendant(
        of: find.byType(AgentAvatar),
        matching: find.byType(Image),
      ));
      expect((image.image as AssetImage).assetName, agent.asset);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('three faces, three different files', (tester) async {
    // Two agents sharing an avatar is the "skin" failure in its most visible
    // form: the picker shows the same creature twice.
    final assets = Agent.all.map((a) => a.asset).toSet();
    expect(assets.length, 3);
  });
}
