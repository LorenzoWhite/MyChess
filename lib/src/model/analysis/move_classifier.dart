import 'dart:math' as math;

import 'package:lichess_mobile/src/model/analysis/move_quality.dart';

/// Below this loss the move is practically as good as the best one.
const double kExcellentLoss = 0.02;

/// At or above this loss the move is an inaccuracy.
const double kInaccuracyLoss = 0.05;

/// At or above this loss the move is a mistake.
const double kMistakeLoss = 0.10;

/// At or above this loss the move is a blunder.
const double kBlunderLoss = 0.20;

/// The winning chances a move cost its player, clamped to `[0, 1]`.
///
/// A move that improves the position costs nothing. All thresholds are on the `0..1` scale of
/// `Eval.winningChances`, not centipawns: a 100 cp drop means very different things in a quiet
/// equal position and in a won one.
double moveLoss({required double winChancesBefore, required double winChancesAfter}) =>
    math.max(0.0, winChancesBefore - winChancesAfter);

/// The quality of a move, from the winning chances before and after it (both from the mover's
/// point of view) and whether it was the engine's first choice.
///
/// [isBook] wins over everything else: an opening move is not judged by the engine.
MoveQuality classifyMove({
  required double winChancesBefore,
  required double winChancesAfter,
  required bool playedBest,
  bool isBook = false,
}) {
  if (isBook) return .book;

  final lost = moveLoss(winChancesBefore: winChancesBefore, winChancesAfter: winChancesAfter);
  if (playedBest) return .best;
  if (lost < kExcellentLoss) return .excellent;
  if (lost < kInaccuracyLoss) return .good;
  if (lost < kMistakeLoss) return .inaccuracy;
  if (lost < kBlunderLoss) return .mistake;
  return .blunder;
}
