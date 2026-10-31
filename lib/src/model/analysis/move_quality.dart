/// How good a move was, chess.com-style.
///
/// Deliberately separate from [MoveVerdict] in `engine/practice_comment.dart`: that one judges a
/// move during practice and is tuned for "did you throw the exercise away", with its own
/// thresholds and symbols. Changing it would change practice mode.
enum MoveQuality(
  /// The annotation glyph shown next to the move, empty when the move is unannotated.
  final String symbol,
  final String label,
) {
  /// A move from the opening book.
  book('', 'Book'),

  /// A sound sacrifice that keeps the position won. Only produced once the heuristic exists.
  brilliant('!!', 'Brilliant'),

  /// The only move that keeps the position. Only produced once the heuristic exists.
  great('!', 'Great'),

  /// The engine's first choice.
  best('', 'Best'),

  /// Not the best move, but practically as good.
  excellent('', 'Excellent'),

  /// A reasonable move that gives up a little.
  good('', 'Good'),

  /// A visible drop.
  inaccuracy('?!', 'Inaccuracy'),

  /// A serious drop.
  mistake('?', 'Mistake'),

  /// A winning tactic went begging. Only produced once the heuristic exists.
  miss('✗', 'Miss'),

  /// A game-changing drop.
  blunder('??', 'Blunder');

  /// Whether the move deserves a glyph in the move list.
  bool get hasSymbol => symbol.isNotEmpty;

  /// Whether this counts as a mistake in the summary counts.
  bool get isMistake => this == inaccuracy || this == mistake || this == blunder;
}

/// The PGN NAG code that stands for [quality], or null when the move carries no glyph.
///
/// Used both for the move list and for the annotation badge on the board, so that the two can never
/// disagree.
int? nagForQuality(MoveQuality quality) => switch (quality) {
  .brilliant => 3,
  .great => 1,
  .inaccuracy => 6,
  .mistake => 2,
  .miss => 5,
  .blunder => 4,
  _ => null,
};
