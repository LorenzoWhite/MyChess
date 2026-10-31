import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/game_report.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/eval.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/node.dart';
import 'package:lichess_mobile/src/model/engine/evaluation_context.dart';
import 'package:lichess_mobile/src/model/engine/position_evaluator.dart';
import 'package:lichess_mobile/src/model/engine/practice_analyser.dart';
import 'package:lichess_mobile/src/model/engine/work.dart';

/// How long the engine may spend on one position of the report.
const kReportSearchTime = Duration(milliseconds: 900);

/// How long a position may take to reach [_kReportMinDepth] before it is judged as it stands.
const kReportWaitTimeout = Duration(seconds: 2);

/// The depth a report is happy with. Lower than practice: a report is about relative quality
/// across a whole game, not about being sure of the single best move.
const int _kReportMinDepth = 12;

/// The state of a game report.
class GameReportState {
  const new({this.report, this.done = 0, this.total = 0, this.error});

  const new idle() : report = null, done = 0, total = 0, error = null;

  final GameReport? report;

  /// Positions evaluated so far, out of [total]. `total` is 0 when idle.
  final int done;
  final int total;

  final Object? error;

  bool get isRunning => total > 0 && report == null && error == null;

  /// 0..1, for a progress bar.
  double get progress => total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

  GameReportState copyWith({GameReport? report, int? done, int? total, Object? error}) =>
      GameReportState(
        report: report ?? this.report,
        done: done ?? this.done,
        total: total ?? this.total,
        error: error ?? this.error,
      );
}

final gameReportProvider = NotifierProvider.autoDispose
    .family<GameReportController, GameReportState, StringId>(
      GameReportController.new,
      name: 'GameReportProvider',
    );

/// Judges every move of a game by evaluating every position along its mainline.
///
/// Deliberately separate from the analysis board's own engine use: it borrows the position
/// evaluator for the same context so the engine is already warm, but it does not move the board.
class GameReportController(final StringId id) extends Notifier<GameReportState> {
  PracticeAnalyser? _analyser;

  @override
  GameReportState build() {
    ref.onDispose(() {
      _analyser?.dispose();
      _analyser = null;
    });
    return const GameReportState.idle();
  }

  void cancel() {
    _analyser?.dispose();
    _analyser = null;
    state = const GameReportState.idle();
  }

  Future<void> analyse({required Variant variant, required String pgn}) async {
    if (state.isRunning) return;

    final root = Root.fromPgnGame(PgnGame.parsePgn(pgn));
    final mainline = root.mainline.toList();
    if (mainline.isEmpty) return;
    final steps = mainline.map(Step.fromNode).toList();

    final context = EvaluationContext(
      id: StringId('report-$id'),
      variant: variant,
      initialPosition: root.position,
    );
    // Keeps the evaluator alive for as long as this controller is.
    ref.listen(positionEvaluatorProvider(context), (_, _) {});

    final analyser = _analyser = PracticeAnalyser(
      ref: ref,
      evaluator: () => ref.read(positionEvaluatorProvider(context).notifier),
      alwaysRequestCloudEvals: false,
      onEval: (_, _) {},
    );

    final total = steps.length + 1;
    state = GameReportState(total: total);

    try {
      final evals = <ClientEval?>[];
      for (var i = 0; i <= steps.length; i++) {
        if (!ref.mounted) return;
        final position = i == 0 ? root.position : steps[i - 1].position;

        analyser.analyse(
          EvalWork(
            id: context.id,
            variant: variant,
            threads: 1,
            searchTime: kReportSearchTime,
            multiPv: 1,
            threatMode: false,
            initialPosition: root.position,
            steps: steps.take(i).toList().lock,
          ),
        );
        evals.add(
          await analyser.usableEval(
            position,
            timeout: kReportWaitTimeout,
            minDepth: _kReportMinDepth,
          ),
        );
        if (!ref.mounted) return;
        state = state.copyWith(done: i + 1);
      }

      if (!ref.mounted) return;
      state = GameReportState(
        report: buildGameReport(steps: steps, evals: evals),
        done: total,
        total: total,
      );
    } catch (e) {
      if (ref.mounted) state = GameReportState(error: e, total: total);
    } finally {
      analyser.dispose();
      _analyser = null;
    }
  }
}
