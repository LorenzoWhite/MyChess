import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:material_ui/material_ui.dart';

/// Length of the intro from a search.
const _kTotalMs = 800;

const _kCardOutMs = 220;
const _kTopTableStartMs = 220;
const _kTopTableEndMs = 580;
const _kBottomTableStartMs = 290;
const _kBottomTableEndMs = 650;
const _kBottomBarStartMs = 400;
const _kBottomBarEndMs = 800;

/// When the first pieces start dropping.
const _kPiecesStartMs = 60;

/// How long each piece takes to land.
const _kPieceMs = 320;

/// Delay between rings of files, from the centre (d and e files) to the edges (a and h files).
const _kRingDelayMs = 45;

/// Delay of the pawns after the piece behind them.
const _kPawnDelayMs = 40;

/// When the last piece (a pawn on the a or h file) has landed.
const _kPiecesEndMs = _kPiecesStartMs + 3 * _kRingDelayMs + _kPawnDelayMs + _kPieceMs;

/// How far away a piece starts its drop, in squares: the player's pieces rise from below their
/// square, the opponent's come down from above.
const _kDropDistance = 0.45;

/// How much bigger than its square a piece starts, as if it were lifted off the board.
const _kDropScale = 1.12;

/// How long each piece of a previous game takes to leave the board.
const _kClearPieceMs = 240;

/// Delay between rings of files when clearing, from the edges (a and h files) to the centre.
const _kClearRingDelayMs = 30;

/// Delay of the pieces after the pawns in front of them when clearing.
const _kClearBehindDelayMs = 30;

/// When the last piece of a previous game has left the board.
const _kClearEndMs = 3 * _kClearRingDelayMs + _kClearBehindDelayMs + _kClearPieceMs;

/// How long after the previous game's pieces start leaving the new ones start dropping. Everything
/// after the clearing is shifted by this much.
const _kClearLeadMs = 200;

/// How far a leaving piece travels, in squares, towards its owner's side of the board.
const _kClearDistance = 0.3;

/// A board as it was shown: its pieces and orientation. What the intro clears off the board.
typedef MatchIntroBoard = ({Pieces pieces, Side orientation});

/// When each part of the intro plays, as [Interval]s of the intro animation (0 to 1).
class const MatchIntroTimeline({
  /// Whether the intro starts by clearing a previous game's pieces off the board, which shifts
  /// everything else.
  final bool clearsBoard = false,
}) {
  int get _leadMs => clearsBoard ? _kClearLeadMs : 0;

  int get _totalMs => _kTotalMs + _leadMs;

  Duration get duration => Duration(milliseconds: _totalMs);

  Interval _interval(int startMs, int endMs, Curve curve) =>
      Interval((startMs + _leadMs) / _totalMs, (endMs + _leadMs) / _totalMs, curve: curve);

  /// The search card shrinks and fades out.
  Interval get card => Interval(0.0, _kCardOutMs / _totalMs, curve: Curves.easeIn);

  /// The opponent's table slides down into place.
  Interval get topTable => _interval(_kTopTableStartMs, _kTopTableEndMs, Curves.easeOutCubic);

  /// The player's table slides up into place.
  Interval get bottomTable =>
      _interval(_kBottomTableStartMs, _kBottomTableEndMs, Curves.easeOutCubic);

  /// The game buttons fade in.
  Interval get bottomBar => _interval(_kBottomBarStartMs, _kBottomBarEndMs, Curves.easeOut);

  /// The last piece has landed: from here the board shows the real position.
  double get piecesLanded => (_kPiecesEndMs + _leadMs) / _totalMs;
}

/// The match intro: the short sequence played on the game board when a new game takes over the
/// screen, so that it hands over to the game instead of cutting to it.
///
/// From a search, the search card is drawn on the game board exactly as the search screen left it,
/// then shrinks and fades out while the pieces drop onto their squares in a wave from the centre files
/// outwards. The player tables then slide in from the screen edges and the game buttons fade in.
///
/// From a finished game (a rematch), the previous game's pieces are first lifted off the board, from
/// the edges inwards, and the new ones drop in as they go. The player tables stay in place.
///
/// Everything runs off one [AnimationController] of [MatchIntroTimeline.duration]; the timeline places
/// each part on it. The intro never blocks the game: any pointer down on the game screen skips to its
/// end, and so does a position change from the server.
///
/// This class holds what the game board needs to play it.
class const MatchIntro({
  /// The search card, built exactly as the search screen showed it when the game was found. Null
  /// when the game does not come from a search.
  final Widget? card,

  /// The previous game's board, to clear before the new pieces drop in.
  final MatchIntroBoard? clearing,

  /// Whether the player tables slide in. Not when a previous game's tables were already in place.
  final bool tablesEnter = true,

  /// Called when the board starts the intro, so the screen plays it only once per game.
  required final VoidCallback onStarted,
}) {
  MatchIntroTimeline get timeline => MatchIntroTimeline(clearsBoard: clearing != null);
}

/// The search card over the board at the start of the intro, shrinking and fading out.
///
/// Builds nothing once the card is gone, so it stops listening to the lobby.
class const MatchIntroCard({
  required final Animation<double> animation,
  required final MatchIntroTimeline timeline,
  required final Widget card,
}) extends StatefulWidget {
  @override
  State<MatchIntroCard> createState() => _MatchIntroCardState();
}

class _MatchIntroCardState() extends State<MatchIntroCard> {
  late bool _gone = _isGone;

  bool get _isGone => widget.animation.value >= widget.timeline.card.end;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_onTick);
  }

  @override
  void didUpdateWidget(MatchIntroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_onTick);
      widget.animation.addListener(_onTick);
      _onTick();
    }
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (_isGone != _gone) setState(() => _gone = _isGone);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final out = widget.animation.drive(CurveTween(curve: widget.timeline.card));
    return IgnorePointer(
      child: FadeTransition(
        opacity: out.drive(Tween(begin: 1.0, end: 0.0)),
        child: ScaleTransition(scale: out.drive(Tween(begin: 1.0, end: 0.94)), child: widget.card),
      ),
    );
  }
}

/// Draws the intro's pieces while [animation] runs: [clearing]'s pieces leaving the board, then
/// [pieces] dropping onto their squares. Draws nothing once they have all landed: the board
/// underneath then shows the real position.
///
/// Must cover the board's squares exactly (inside any border), like chessground's own pieces.
class const MatchIntroPieces({
  required final Animation<double> animation,
  required final MatchIntroTimeline timeline,
  required final Pieces pieces,
  required final Side orientation,
  required final PieceAssets pieceAssets,
  final MatchIntroBoard? clearing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _IntroPiecesPainter(
            animation: animation,
            totalMs: timeline.duration.inMilliseconds,
            dropLeadMs: timeline._leadMs,
            pieces: pieces,
            orientation: orientation,
            clearing: clearing,
            pieceAssets: pieceAssets,
          ),
        ),
      ),
    );
  }
}

/// Lifts [board]'s pieces off the board once, when first shown: used by a search screen that
/// replaces a finished game, so the previous game doesn't vanish in one frame.
///
/// Must cover the board's squares exactly, like [MatchIntroPieces].
class const MatchIntroClearPieces({required final MatchIntroBoard board})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<MatchIntroClearPieces> createState() => _MatchIntroClearPiecesState();
}

class _MatchIntroClearPiecesState()
    extends ConsumerState<MatchIntroClearPieces>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _kClearEndMs),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduce-motion: the previous game's pieces are just gone.
    if (MediaQuery.disableAnimationsOf(context)) {
      _clear.value = 1.0;
    } else if (_clear.status == AnimationStatus.dismissed) {
      _clear.forward();
    }
  }

  @override
  void dispose() {
    _clear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pieceAssets = ref.watch(boardPreferencesProvider.select((p) => p.pieceSet.assets));
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _IntroPiecesPainter(
            animation: _clear,
            totalMs: _kClearEndMs,
            dropLeadMs: 0,
            pieces: const {},
            orientation: widget.board.orientation,
            clearing: widget.board,
            pieceAssets: pieceAssets,
          ),
        ),
      ),
    );
  }
}

class _IntroPiecesPainter({
  required final Animation<double> animation,

  /// Length of [animation], to tell how far into the intro it is.
  required final int totalMs,

  /// When the pieces start dropping, after the clearing has started.
  required final int dropLeadMs,
  required final Pieces pieces,
  required final Side orientation,
  required final MatchIntroBoard? clearing,
  required final PieceAssets pieceAssets,
}) extends CustomPainter {
  this : super(repaint: animation);

  static int _dropDelayMs(Square square, Piece piece) {
    final ring = (square.file - 3.5).abs().floor();
    return _kPiecesStartMs + ring * _kRingDelayMs + (piece.role == Role.pawn ? _kPawnDelayMs : 0);
  }

  static int _clearDelayMs(Square square, Piece piece) {
    final ringFromEdge = 3 - (square.file - 3.5).abs().floor();
    return ringFromEdge * _kClearRingDelayMs + (piece.role == Role.pawn ? 0 : _kClearBehindDelayMs);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final elapsedMs = animation.value * totalMs;
    final squareSize = size.width / 8;

    final clearing = this.clearing;
    if (clearing != null && elapsedMs < _kClearEndMs) {
      for (final MapEntry(key: square, value: piece) in clearing.pieces.entries) {
        final t = ((elapsedMs - _clearDelayMs(square, piece)) / _kClearPieceMs).clamp(0.0, 1.0);
        if (t == 1.0) continue;
        _drawPiece(
          canvas,
          squareSize,
          square,
          piece,
          clearing.orientation,
          // Picked up and taken back towards its owner's side of the board.
          shift:
              Curves.easeInCubic.transform(t) *
              _kClearDistance *
              squareSize *
              (piece.color == clearing.orientation ? 1 : -1),
          scale: 1 + (_kDropScale - 1) * Curves.easeOutCubic.transform(t),
          opacity: 1 - Curves.easeIn.transform(t),
        );
      }
    }

    final dropMs = elapsedMs - dropLeadMs;
    if (dropMs >= _kPiecesEndMs) return;
    for (final MapEntry(key: square, value: piece) in pieces.entries) {
      final t = ((dropMs - _dropDelayMs(square, piece)) / _kPieceMs).clamp(0.0, 1.0);
      if (t == 0.0) continue;
      _drawPiece(
        canvas,
        squareSize,
        square,
        piece,
        orientation,
        // easeOutBack overshoots a little, so the piece settles into its square.
        shift:
            (1 - Curves.easeOutBack.transform(t)) *
            _kDropDistance *
            squareSize *
            (piece.color == orientation ? 1 : -1),
        scale: 1 + (_kDropScale - 1) * (1 - Curves.easeOutCubic.transform(t)),
        opacity: Curves.easeOut.transform((t / 0.6).clamp(0.0, 1.0)),
      );
    }
  }

  /// Draws [piece] on [square], moved down by [shift] (up if negative) and scaled around its centre.
  void _drawPiece(
    Canvas canvas,
    double squareSize,
    Square square,
    Piece piece,
    Side orientation, {
    required double shift,
    required double scale,
    required double opacity,
  }) {
    final asset = pieceAssets[piece.kind];
    if (asset == null) return;
    final image = ChessgroundImages.instance.get(asset);
    if (image == null) return;

    final x = orientation == Side.white ? square.file : 7 - square.file;
    final y = orientation == Side.white ? 7 - square.rank : square.rank;
    final dst = Rect.fromCenter(
      center: Offset((x + 0.5) * squareSize, (y + 0.5) * squareSize + shift),
      width: squareSize * scale,
      height: squareSize * scale,
    );
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }

  @override
  bool shouldRepaint(_IntroPiecesPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.totalMs != totalMs ||
      oldDelegate.dropLeadMs != dropLeadMs ||
      oldDelegate.pieces != pieces ||
      oldDelegate.orientation != orientation ||
      oldDelegate.clearing != clearing ||
      oldDelegate.pieceAssets != pieceAssets;
}

/// Slides [child] in from [from] (a fraction of its size, as for [SlideTransition]) and fades it in
/// during [interval] of the intro [animation].
///
/// With [kAlwaysCompleteAnimation] it shows [child] as is, so callers can keep the same widget tree
/// whether or not an intro plays.
class const MatchIntroEntrance({
  required final Animation<double> animation,
  required final Interval interval,
  final Offset from = Offset.zero,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final progress = animation.drive(CurveTween(curve: interval));
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: progress.drive(Tween(begin: from, end: Offset.zero)),
        child: child,
      ),
    );
  }
}
