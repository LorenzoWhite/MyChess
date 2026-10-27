import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/settings/quick_match_preferences.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the sheet that configures the two quick match tiles.
Future<void> showQuickMatchesSheet(BuildContext context) {
  return showAdaptiveBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => const QuickMatchesSheet(),
  );
}

/// Configures what the tiles above and below Play start.
class const QuickMatchesSheet() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(quickMatchPreferencesProvider);
    final notifier = ref.read(quickMatchPreferencesProvider.notifier);

    return BottomSheetScrollableContainer(
      padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
          child: Text('Quick matches', style: Theme.of(context).textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 8.0),
          child: Text(
            'The tiles above and below Play. Automatic learns from the games you start.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final side in QuickMatchSide.values)
          _SlotSection(
            side: side,
            prefs: prefs,
            onModeChanged: (mode) => notifier.setMode(side, mode),
            onPinned: (timeControl) => notifier.pin(side, timeControl),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
          child: FilledButton(
            onPressed: () {
              notifier.markConfigured();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}

class const _SlotSection({
  required final QuickMatchSide side,
  required final QuickMatchPrefs prefs,
  required final ValueChanged<QuickMatchMode> onModeChanged,
  required final ValueChanged<TimeIncrement> onPinned,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final slot = prefs.slot(side);
    final resolved = prefs.resolve(side);
    final theme = Theme.of(context);
    final isUp = side == QuickMatchSide.up;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isUp ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
              const SizedBox(width: 8.0),
              Text(
                isUp ? 'Above Play' : 'Below Play',
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              Text(
                '${resolved.display} · ${resolved.speed.label(context.l10n)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8.0),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Automatic'),
                selected: slot.mode == QuickMatchMode.automatic,
                onSelected: (_) => onModeChanged(QuickMatchMode.automatic),
              ),
              const SizedBox(width: 8.0),
              ChoiceChip(
                label: const Text('Pin'),
                selected: slot.mode == QuickMatchMode.pinned,
                onSelected: (_) => onModeChanged(QuickMatchMode.pinned),
              ),
            ],
          ),
          if (slot.mode == QuickMatchMode.pinned) ...[
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [
                for (final timeControl in TimeIncrement.matrixPresets)
                  _PresetChip(
                    timeControl: timeControl,
                    selected: slot.pinned == timeControl,
                    onTap: () => onPinned(timeControl),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 4.0),
            Text(
              'Learned from your recent games',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class const _PresetChip({
  required final TimeIncrement timeControl,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Text(
          timeControl.display,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? Theme.of(context).colorScheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }
}
