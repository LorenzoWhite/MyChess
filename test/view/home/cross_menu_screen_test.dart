import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/quick_match_preferences.dart';
import 'package:lichess_mobile/src/view/home/cross_menu_screen.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('sliding back out of the quick matches returns the rook to the centre', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // A configured device, so the tiles show time controls instead of the set-up prompt.
          quickMatchPreferencesProvider.overrideWith(_ConfiguredQuickMatches.new),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: CrossMenuScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));

    // cellSize = min(width * 0.27, height * 0.17) with a 540 x 1000 logical screen.
    const cell = 540 * 0.27;

    final gesture = await tester.startGesture(tester.getCenter(find.byType(CrossMenuScreen)));

    // Fingers deliver many small deltas, so simulate the drag in small steps.
    Future<void> slide(double total) async {
      const steps = 80;
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(total / steps, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // Slide right past the second-level hand-over (0.92 cell).
    await slide(cell * 1.2);
    expect(find.text('10+0'), findsOneWidget, reason: 'quick matches should be revealed');

    final atPlay = tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
    expect(atPlay.left, closeTo(2 * cell, 1.0), reason: 'rook should be on the Play column');

    // Slide back left, heading home.
    await slide(-cell * 2.0);

    final backHome = tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned));
    expect(
      backHome.left,
      lessThan(1.5 * cell),
      reason: 'rook must leave the Play column and head back to the centre',
    );

    final quickFade = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('10+0'), matching: find.byType(AnimatedOpacity)).first,
    );
    expect(
      quickFade.opacity,
      lessThan(0.1),
      reason: 'the quick matches should collapse while backing out',
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

class _ConfiguredQuickMatches() extends QuickMatchPreferences {
  @override
  QuickMatchPrefs build() => QuickMatchPrefs.defaults.copyWith(isConfigured: true);
}
