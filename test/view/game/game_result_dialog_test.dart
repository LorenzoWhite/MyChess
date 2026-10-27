import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';
// Reuse the finished-game fixture and its mock client.
import 'game_back_to_tournament_test.dart' as fixtures;

const _gameId = GameFullId('qVChCOTcHSeW');

void main() {
  testWidgets('result dialog actions are live immediately and still fade in', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const GameScreen(source: ExistingGameSource(_gameId)),
      overrides: {
        lichessClientProvider: lichessClientProvider.overrideWith(
          (ref) => LichessClient(fixtures.tournamentMockClient(), ref),
        ),
      },
    );
    await tester.pumpWidget(app);

    await fixtures.showResultDialog(tester);

    final backHome = find.widgetWithText(FilledButton, 'Back to home');
    expect(backHome, findsOneWidget);
    expect(
      tester.widget<FilledButton>(backHome).onPressed,
      isNotNull,
      reason: 'there is no arming guard: actions are live immediately',
    );

    final actions = find.byKey(const ValueKey('game-result-actions'));
    expect(
      tester.widget<Opacity>(actions).opacity,
      lessThan(1.0),
      reason: 'the entrance is still animating on the first frame',
    );

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.widget<Opacity>(actions).opacity, 1.0);
  });
}
