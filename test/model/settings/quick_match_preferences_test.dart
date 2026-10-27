import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/settings/quick_match_preferences.dart';

void main() {
  group('QuickMatchPrefs', () {
    test('falls back to 10+0 above and 5+0 below with no history', () {
      const prefs = QuickMatchPrefs.defaults;

      expect(prefs.resolve(QuickMatchSide.up), const TimeIncrement(600, 0));
      expect(prefs.resolve(QuickMatchSide.down), const TimeIncrement(300, 0));
    });

    test('a pinned tile ignores the history', () {
      final prefs = QuickMatchPrefs.defaults.copyWith(
        down: const QuickMatchSlot(mode: QuickMatchMode.pinned, pinned: TimeIncrement(180, 2)),
        recent: [const TimeIncrement(600, 0)].lock,
      );

      expect(prefs.resolve(QuickMatchSide.down), const TimeIncrement(180, 2));
    });

    test('automatic picks the most played control, ties broken by recency', () {
      final prefs = QuickMatchPrefs.defaults.copyWith(
        up: const QuickMatchSlot.automatic(),
        down: const QuickMatchSlot.automatic(),
        recent: [
          const TimeIncrement(300, 0),
          const TimeIncrement(600, 0),
          const TimeIncrement(300, 0),
        ].lock,
      );

      expect(prefs.resolve(QuickMatchSide.down), const TimeIncrement(300, 0));
      expect(prefs.resolve(QuickMatchSide.up), const TimeIncrement(600, 0));
    });

    test('the two tiles never resolve to the same control', () {
      final prefs = QuickMatchPrefs.defaults.copyWith(
        up: const QuickMatchSlot.automatic(),
        down: QuickMatchSlot.defaultDown,
        recent: [const TimeIncrement(300, 0)].lock,
      );

      expect(prefs.resolve(QuickMatchSide.up), isNot(prefs.resolve(QuickMatchSide.down)));
    });

    test('survives a json round trip', () {
      final prefs = QuickMatchPrefs.defaults.copyWith(
        isConfigured: true,
        recent: [const TimeIncrement(180, 2), const TimeIncrement(600, 0)].lock,
      );

      final restored = QuickMatchPrefs.fromJson(prefs.toJson());

      expect(restored.isConfigured, isTrue);
      expect(restored.recent, hasLength(2));
      expect(restored.recent.first, const TimeIncrement(180, 2));
      expect(restored.resolve(QuickMatchSide.down), prefs.resolve(QuickMatchSide.down));
    });
  });
}
