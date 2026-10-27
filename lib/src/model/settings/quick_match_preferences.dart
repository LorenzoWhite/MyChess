import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/settings/preferences_storage.dart';

/// The two quick match tiles shown above and below the Play arm.
enum QuickMatchSide() {
  /// Above Play.
  up,

  /// Below Play.
  down,
}

/// How a quick match tile picks its time control.
enum QuickMatchMode() {
  /// Learned from the time controls of recently started real-time games.
  automatic,

  /// Chosen by the user.
  pinned,
}

/// One quick match tile: either learned or pinned.
@immutable
class QuickMatchSlot {
  const new({required this.mode, this.pinned});

  const new automatic() : mode = QuickMatchMode.automatic, pinned = null;

  final QuickMatchMode mode;

  /// Only set when [mode] is [QuickMatchMode.pinned].
  final TimeIncrement? pinned;

  static const defaultUp = QuickMatchSlot(
    mode: QuickMatchMode.pinned,
    pinned: TimeIncrement(600, 0),
  );

  static const defaultDown = QuickMatchSlot(
    mode: QuickMatchMode.pinned,
    pinned: TimeIncrement(300, 0),
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    if (pinned != null) 'pinned': pinned!.toJson(),
  };

  factory fromJson(Map<String, dynamic> json) => QuickMatchSlot(
    mode: QuickMatchMode.values.firstWhere(
      (mode) => mode.name == json['mode'],
      orElse: () => QuickMatchMode.pinned,
    ),
    pinned: json['pinned'] == null
        ? null
        : TimeIncrement.fromJson(json['pinned'] as Map<String, dynamic>),
  );

  QuickMatchSlot copyWith({QuickMatchMode? mode, TimeIncrement? pinned}) =>
      QuickMatchSlot(mode: mode ?? this.mode, pinned: pinned ?? this.pinned);
}

/// Per-device preferences for the two quick match tiles.
///
/// Nothing here is per-account: the learned history is simply the time controls of real-time games
/// started on this device, most recent first.
@immutable
class const QuickMatchPrefs({
  required final QuickMatchSlot up,
  required final QuickMatchSlot down,

  /// False until the first-run setup has been completed, so the tiles can advertise themselves.
  required final bool isConfigured,

  /// Time controls of recently started real-time games, most recent first.
  required final IList<TimeIncrement> recent,
}) implements Serializable {
  /// How many started games are remembered when learning.
  static const historyLength = 20;

  static const _fallbackUp = TimeIncrement(600, 0);
  static const _fallbackDown = TimeIncrement(300, 0);

  static const defaults = QuickMatchPrefs(
    up: QuickMatchSlot.defaultUp,
    down: QuickMatchSlot.defaultDown,
    isConfigured: false,
    recent: IListConst([]),
  );

  QuickMatchSlot slot(QuickMatchSide side) => side == QuickMatchSide.up ? up : down;

  /// The distinct time controls of recent games, most played first, ties broken by recency.
  List<TimeIncrement> ranked() {
    final counts = <TimeIncrement, int>{};
    final lastSeen = <TimeIncrement, int>{};
    for (var i = 0; i < recent.length; i++) {
      final timeControl = recent[i];
      counts[timeControl] = (counts[timeControl] ?? 0) + 1;
      lastSeen.putIfAbsent(timeControl, () => i);
    }
    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        if (byCount != 0) return byCount;
        return lastSeen[a]!.compareTo(lastSeen[b]!);
      });
    return ranked;
  }

  /// The time control a tile currently stands for.
  ///
  /// The down tile is the primary one (your most played), the up tile the secondary (your second
  /// most played). Pinned tiles ignore the history.
  TimeIncrement resolve(QuickMatchSide side) {
    final current = slot(side);
    if (current.mode == QuickMatchMode.pinned && current.pinned != null) {
      return current.pinned!;
    }

    final ordered = ranked();
    if (side == QuickMatchSide.down) {
      return ordered.isNotEmpty ? ordered.first : _fallbackDown;
    }

    final downValue = resolve(QuickMatchSide.down);
    for (final candidate in ordered) {
      if (candidate != downValue) return candidate;
    }
    // Never show the same control on both tiles.
    return downValue == _fallbackUp ? _fallbackDown : _fallbackUp;
  }

  QuickMatchPrefs copyWith({
    QuickMatchSlot? up,
    QuickMatchSlot? down,
    bool? isConfigured,
    IList<TimeIncrement>? recent,
  }) => QuickMatchPrefs(
    up: up ?? this.up,
    down: down ?? this.down,
    isConfigured: isConfigured ?? this.isConfigured,
    recent: recent ?? this.recent,
  );

  factory fromJson(Map<String, dynamic> json) => QuickMatchPrefs(
    up: json['up'] == null
        ? QuickMatchSlot.defaultUp
        : QuickMatchSlot.fromJson(json['up'] as Map<String, dynamic>),
    down: json['down'] == null
        ? QuickMatchSlot.defaultDown
        : QuickMatchSlot.fromJson(json['down'] as Map<String, dynamic>),
    isConfigured: json['isConfigured'] as bool? ?? false,
    recent:
        (json['recent'] as List<dynamic>?)
            ?.map((e) => TimeIncrement.fromJson(e as Map<String, dynamic>))
            .toList()
            .lock ??
        const IListConst([]),
  );

  @override
  Map<String, dynamic> toJson() => {
    'up': up.toJson(),
    'down': down.toJson(),
    'isConfigured': isConfigured,
    'recent': recent.map((timeControl) => timeControl.toJson()).toList(),
  };
}

final quickMatchPreferencesProvider = NotifierProvider<QuickMatchPreferences, QuickMatchPrefs>(
  QuickMatchPreferences.new,
  name: 'QuickMatchPreferencesProvider',
);

class QuickMatchPreferences()
    extends Notifier<QuickMatchPrefs>
    with PreferencesStorage<QuickMatchPrefs> {
  @override
  @protected
  PrefCategory get prefCategory => PrefCategory.quickMatch;

  @override
  @protected
  QuickMatchPrefs get defaults => QuickMatchPrefs.defaults;

  @override
  QuickMatchPrefs fromJson(Map<String, dynamic> json) => QuickMatchPrefs.fromJson(json);

  @override
  QuickMatchPrefs build() => fetch();

  Future<void> setSlot(QuickMatchSide side, QuickMatchSlot slot) {
    return save(side == QuickMatchSide.up ? state.copyWith(up: slot) : state.copyWith(down: slot));
  }

  Future<void> setMode(QuickMatchSide side, QuickMatchMode mode) {
    if (mode == QuickMatchMode.automatic) {
      return setSlot(side, const QuickMatchSlot.automatic());
    }
    // Pinning keeps whatever the tile currently shows, so the value does not jump.
    return pin(side, state.resolve(side));
  }

  Future<void> pin(QuickMatchSide side, TimeIncrement timeControl) =>
      setSlot(side, QuickMatchSlot(mode: QuickMatchMode.pinned, pinned: timeControl));

  /// Remembers a time control used for a real-time game started on this device.
  Future<void> recordPlayed(TimeIncrement timeControl) {
    final history = [timeControl, ...state.recent];
    return save(state.copyWith(recent: history.take(QuickMatchPrefs.historyLength).toList().lock));
  }

  Future<void> markConfigured() {
    if (state.isConfigured) return Future.value();
    return save(state.copyWith(isConfigured: true));
  }
}
