import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/analysis/game_report.dart';
import 'package:lichess_mobile/src/model/analysis/game_report_controller.dart';
import 'package:lichess_mobile/src/model/analysis/move_quality.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showGameReportSheet(
  BuildContext context, {
  required StringId id,
  required Variant variant,
  required String pgn,
}) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GameReportSheet(id: id, variant: variant, pgn: pgn),
  );
}

class const _GameReportSheet({
  required final StringId id,
  required final Variant variant,
  required final String pgn,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameReportProvider(id));
    final theme = Theme.of(context);

    return BottomSheetScrollableContainer(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
      children: [
        Text('Game report', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8.0),
        if (state.report == null && !state.isRunning) ...[
          Text(
            'Judge every move of this game with the engine. It takes a minute or two.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16.0),
          FilledButton(
            onPressed: () =>
                ref.read(gameReportProvider(id).notifier).analyse(variant: variant, pgn: pgn),
            child: const Text('Analyse game'),
          ),
        ],
        if (state.isRunning) ...[
          Text(
            'Evaluating ${state.done} of ${state.total} positions…',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8.0),
          LinearProgressIndicator(value: state.progress),
        ],
        if (state.error != null)
          Text(
            'Could not finish the report.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        if (state.report case final report?) ...[
          _SideReport(name: 'White', report: report.white),
          const SizedBox(height: 8.0),
          _SideReport(name: 'Black', report: report.black),
          const SizedBox(height: 8.0),
          Text(
            'Judged from a short engine search, so expect the odd disagreement.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class const _SideReport({required final String name, required final PlayerReport report})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accuracy = report.accuracy.toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('$accuracy%', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4.0),
            Wrap(
              spacing: 12.0,
              children: [
                _Count(label: 'Inaccuracies', value: report.countOf(MoveQuality.inaccuracy)),
                _Count(label: 'Mistakes', value: report.countOf(MoveQuality.mistake)),
                _Count(label: 'Blunders', value: report.countOf(MoveQuality.blunder)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const _Count({required final String label, required final int value})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text('$label: $value', style: Theme.of(context).textTheme.bodySmall);
  }
}
