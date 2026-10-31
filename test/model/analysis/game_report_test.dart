import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/analysis/game_report.dart';
import 'package:lichess_mobile/src/model/analysis/move_quality.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/engine/work.dart';

LocalEval localEval(int cp, {String? best, required Position position}) => LocalEval(
  position: position,
  searchTime: const Duration(seconds: 1),
  cp: cp,
  depth: 20,
  nodes: 1000,
  millis: 1000,
  pvs: IList([
    PvData(moves: IList([?best])),
  ]),
  threatMode: false,
);

void main() {
  group('buildGameReport', () {
    final root = Root.fromPgnGame(PgnGame.parsePgn('1. e4 e5 2. Nf3'));
    final mainline = root.mainline.toList();
    final steps = mainline.map(Step.fromNode).toList();

    List<ClientEval?> evals({int afterE5 = 400}) => [
      localEval(0, best: 'e2e4', position: root.position),
      localEval(0, best: 'c7c5', position: mainline[0].position),
      localEval(afterE5, best: 'g1f3', position: mainline[1].position),
      localEval(afterE5, position: mainline[2].position),
    ];

    test('marks the engine first choice as best', () {
      final report = buildGameReport(steps: steps, evals: evals());

      expect(report.atPly(1)!.quality, MoveQuality.best);
      expect(report.atPly(1)!.side, Side.white);
      expect(report.atPly(3)!.quality, MoveQuality.best);
    });

    test('marks a move that threw the game away as a blunder', () {
      final report = buildGameReport(steps: steps, evals: evals());

      expect(report.atPly(2)!.quality, MoveQuality.blunder);
      expect(report.atPly(2)!.side, Side.black);
      expect(report.atPly(2)!.loss, greaterThan(0.5));
    });

    test('counts per player and averages the loss', () {
      final report = buildGameReport(steps: steps, evals: evals());

      expect(report.white.countOf(MoveQuality.best), 2);
      expect(report.black.countOf(MoveQuality.blunder), 1);
      expect(report.white.movesCount, 2);
      expect(report.black.movesCount, 1);
      expect(report.white.averageLoss, 0.0);
      expect(report.black.averageLoss, greaterThan(0.5));
      expect(report.of(Side.black).countOf(MoveQuality.blunder), 1);
    });

    test('skips moves whose position has no evaluation', () {
      final missing = evals()..[1] = null;
      final report = buildGameReport(steps: steps, evals: missing);

      expect(report.moves, hasLength(1));
      expect(report.atPly(1), isNull);
      expect(report.atPly(3), isNotNull);
    });
  });
}
