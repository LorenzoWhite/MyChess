import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/home/cross_menu.dart';

void main() {
  group('CrossMenuController', () {
    test('starts at the centre of the cross', () {
      final controller = CrossMenuController();
      addTearDown(controller.dispose);

      expect(controller.activeDirection, isNull);
      expect(controller.isMoving, isFalse);
    });

    test('moves onto an arm', () {
      final controller = CrossMenuController();
      addTearDown(controller.dispose);

      expect(controller.moveTo(CrossDirection.right), isTrue);
      expect(controller.activeDirection, CrossDirection.right);
      expect(controller.isMoving, isTrue);
    });

    test('ignores a second move while the rook is away', () {
      final controller = CrossMenuController();
      addTearDown(controller.dispose);

      controller.moveTo(CrossDirection.right);

      expect(controller.moveTo(CrossDirection.up), isFalse);
      expect(controller.activeDirection, CrossDirection.right);
    });

    test('reset returns the rook to the centre', () {
      final controller = CrossMenuController();
      addTearDown(controller.dispose);

      controller.moveTo(CrossDirection.down);
      controller.reset();

      expect(controller.activeDirection, isNull);
      expect(controller.isMoving, isFalse);
    });

    test('notifies listeners once per accepted move and reset', () {
      final controller = CrossMenuController();
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.moveTo(CrossDirection.left);
      controller.moveTo(CrossDirection.up); // ignored
      controller.reset();
      controller.reset(); // no-op

      expect(notifications, 2);
    });
  });

  group('cross layout', () {
    test('grid offsets point away from the centre', () {
      expect(CrossDirection.up.gridOffset, (0, -1));
      expect(CrossDirection.right.gridOffset, (1, 0));
      expect(CrossDirection.down.gridOffset, (0, 1));
      expect(CrossDirection.left.gridOffset, (-1, 0));
    });

    test('opposite directions undo each other', () {
      for (final direction in CrossDirection.values) {
        expect(direction.opposite.opposite, direction);
        expect(direction.opposite.gridOffset, (-direction.gridOffset.$1, -direction.gridOffset.$2));
      }
    });

    test('every direction has exactly one entry', () {
      expect(kCrossMenuEntries, hasLength(CrossDirection.values.length));
      expect(
        kCrossMenuEntries.map((entry) => entry.direction).toSet(),
        CrossDirection.values.toSet(),
      );
    });

    test('right is play, as designed so far', () {
      final right = kCrossMenuEntries.firstWhere(
        (entry) => entry.direction == CrossDirection.right,
      );
      expect(right.action, CrossMenuAction.play);
    });
  });
}
