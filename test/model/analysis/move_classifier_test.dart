import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/analysis/move_classifier.dart';
import 'package:lichess_mobile/src/model/analysis/move_quality.dart';

void main() {
  group('classifyMove', () {
    MoveQuality classify(
      double before,
      double after, {
      bool playedBest = false,
      bool isBook = false,
    }) => classifyMove(
      winChancesBefore: before,
      winChancesAfter: after,
      playedBest: playedBest,
      isBook: isBook,
    );

    test('a book move wins over the engine judgement', () {
      expect(classify(0.5, 0.1, isBook: true), MoveQuality.book);
      expect(classify(0.5, 0.5, isBook: true), MoveQuality.book);
    });

    test('the engine first choice is best', () {
      expect(classify(0.5, 0.49, playedBest: true), MoveQuality.best);
    });

    test('moves are graded by the winning chances they cost', () {
      expect(classify(0.5, 0.49), MoveQuality.excellent);
      expect(classify(0.5, 0.47), MoveQuality.good);
      expect(classify(0.5, 0.42), MoveQuality.inaccuracy);
      expect(classify(0.5, 0.35), MoveQuality.mistake);
      expect(classify(0.5, 0.20), MoveQuality.blunder);
    });

    test('each band is judged on its own side of the threshold', () {
      expect(classify(0.5, 0.481), MoveQuality.excellent); // -0.019
      expect(classify(0.5, 0.470), MoveQuality.good); // -0.030
      expect(classify(0.5, 0.440), MoveQuality.inaccuracy); // -0.060
      expect(classify(0.5, 0.350), MoveQuality.mistake); // -0.150
      expect(classify(0.5, 0.250), MoveQuality.blunder); // -0.250
    });

    test('a move that improves the position costs nothing', () {
      expect(classify(0.4, 0.6), MoveQuality.excellent);
      expect(moveLoss(winChancesBefore: 0.4, winChancesAfter: 0.6), 0.0);
    });

    test('loss is clamped to 0..1', () {
      expect(moveLoss(winChancesBefore: 1.0, winChancesAfter: 0.0), 1.0);
      expect(moveLoss(winChancesBefore: 0.0, winChancesAfter: 0.9), 0.0);
    });
  });
}
