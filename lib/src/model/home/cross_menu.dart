import 'package:flutter/foundation.dart';

/// A direction the rook can move on the home screen cross.
///
/// The rook sits in the middle of a 3x3 grid, and each arm of the cross is one move away.
enum CrossDirection() {
  up,
  right,
  down,
  left;

  /// Column and row offset of the arm from the centre of the 3x3 grid.
  (int, int) get gridOffset => switch (this) {
    CrossDirection.up => (0, -1),
    CrossDirection.right => (1, 0),
    CrossDirection.down => (0, 1),
    CrossDirection.left => (-1, 0),
  };

  /// The opposite direction, useful to undo a move.
  CrossDirection get opposite => switch (this) {
    CrossDirection.up => CrossDirection.down,
    CrossDirection.right => CrossDirection.left,
    CrossDirection.down => CrossDirection.up,
    CrossDirection.left => CrossDirection.right,
  };
}

/// What an arm of the home cross leads to.
///
/// Only [play] is settled for now: the other arms are placeholders until the menu design is done.
enum CrossMenuAction() {
  play,
  puzzles,
  learn,
  watch,
}

/// The menu entry shown on one arm of the cross.
@immutable
class const CrossMenuEntry({
  required final CrossDirection direction,
  required final CrossMenuAction action,
  required final String label,
});

/// The arms of the home cross, one per direction.
///
/// Change this list to re-map a direction to a different destination.
const kCrossMenuEntries = <CrossMenuEntry>[
  CrossMenuEntry(direction: CrossDirection.up, action: CrossMenuAction.puzzles, label: 'Puzzles'),
  CrossMenuEntry(direction: CrossDirection.right, action: CrossMenuAction.play, label: 'Play'),
  CrossMenuEntry(direction: CrossDirection.down, action: CrossMenuAction.learn, label: 'Learn'),
  CrossMenuEntry(direction: CrossDirection.left, action: CrossMenuAction.watch, label: 'Watch'),
];

/// Drives the rook on the home cross.
///
/// The rook is either at the centre of the cross ([activeDirection] is null) or on one of the
/// arms. A move is only accepted when the rook is at rest, so double taps cannot queue up two
/// destinations.
class CrossMenuController({
  /// How long the rook takes to slide to an arm.
  final Duration moveDuration = const Duration(milliseconds: 180),
}) extends ChangeNotifier {
  CrossDirection? _activeDirection;

  /// The arm the rook is on, or null when it is at the centre.
  CrossDirection? get activeDirection => _activeDirection;

  /// Whether the rook is on an arm rather than at the centre.
  bool get isMoving => _activeDirection != null;

  /// Starts a move towards [direction].
  ///
  /// Returns false when a move is already in progress.
  bool moveTo(CrossDirection direction) {
    if (_activeDirection != null) return false;
    _activeDirection = direction;
    notifyListeners();
    return true;
  }

  /// Returns the rook to the centre of the cross.
  void reset() {
    if (_activeDirection == null) return;
    _activeDirection = null;
    notifyListeners();
  }
}
