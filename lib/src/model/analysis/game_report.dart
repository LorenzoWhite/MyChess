import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:lichess_mobile/src/model/analysis/move_classifier.dart';
import 'package:lichess_mobile/src/model/analysis/move_quality.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/engine/work.dart';

/// One judged move of a game.
@immutable
class const MoveAnalysis({
  /// 1-based ply of the move.
  required final int ply,

  /// The side that played it.
  required final Side side,
  required final MoveQuality quality,

  /// Winning chances of the mover before and after the move, on the `-1..1` scale of
  /// [Eval.winningChances].
  required final double winChancesBefore,
  required final double winChancesAfter,
  required final Eval evalAfter,
}) {
  /// The winning chances the move cost its player.
  double get loss => moveLoss(winChancesBefore: winChancesBefore, winChancesAfter: winChancesAfter);
}

/// What one player did over a game.
@immutable
class const PlayerReport({
  required final IMap<MoveQuality, int> counts,

  /// Average winning chances lost per move, on the `-1..1` scale.
  required final double averageLoss,
  required final int movesCount,
}) {
  int countOf(MoveQuality quality) => counts[quality] ?? 0;

  /// Rough accuracy in percent, from the average loss.
  ///
  /// Approximates lila's accuracy curve; kept here so the number moves with the classifier until
  /// the exact formula is ported.
  double get accuracy => (100 * (1 - averageLoss)).clamp(0.0, 100.0);
}

/// The judged game.
@immutable
class const GameReport({
  /// Ply (1-based) to analysis.
  required final IMap<int, MoveAnalysis> moves,
  required final PlayerReport white,
  required final PlayerReport black,
}) {
  MoveAnalysis? atPly(int ply) => moves[ply];

  PlayerReport of(Side side) => side == Side.white ? white : black;
}

/// Builds a report from a mainline and the evaluation of every position along it.
///
/// [evals] must hold one entry per position: `evals[0]` is the initial position, `evals[i]` the
/// position after the i-th move. A missing evaluation (engine failure, timeout) skips that move
/// rather than guessing.
GameReport buildGameReport({required List<Step> steps, required List<ClientEval?> evals}) {
  assert(evals.length == steps.length + 1);

  final moves = <int, MoveAnalysis>{};

  for (var i = 0; i < steps.length; i++) {
    final before = evals[i];
    final after = evals[i + 1];
    if (before == null || after == null) continue;

    final step = steps[i];
    // A step holds the position the move produced, so the mover is the side that just moved.
    final side = step.position.turn.opposite;
    final playedBest = before.bestMove?.uci == step.sanMove.move.uci;

    moves[i + 1] = MoveAnalysis(
      ply: i + 1,
      side: side,
      quality: classifyMove(
        winChancesBefore: before.winningChances(side),
        winChancesAfter: after.winningChances(side),
        playedBest: playedBest,
      ),
      winChancesBefore: before.winningChances(side),
      winChancesAfter: after.winningChances(side),
      evalAfter: after,
    );
  }

  return GameReport(
    moves: moves.lock,
    white: _playerReport(moves.values.where((move) => move.side == Side.white)),
    black: _playerReport(moves.values.where((move) => move.side == Side.black)),
  );
}

PlayerReport _playerReport(Iterable<MoveAnalysis> moves) {
  final list = moves.toList();
  final counts = <MoveQuality, int>{};
  for (final move in list) {
    counts[move.quality] = (counts[move.quality] ?? 0) + 1;
  }
  final totalLoss = list.fold(0.0, (sum, move) => sum + move.loss);
  return PlayerReport(
    counts: counts.lock,
    averageLoss: list.isEmpty ? 0.0 : totalLoss / list.length,
    movesCount: list.length,
  );
}
