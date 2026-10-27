import 'dart:math' show max, min;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/home/cross_menu.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/settings/quick_match_preferences.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/home/quick_matches_sheet.dart';
import 'package:lichess_mobile/src/view/home/rook_piece.dart';
import 'package:lichess_mobile/src/view/play/play_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Distance the pointer must travel before the drag is locked to an axis.
const _kDragAxisLockThreshold = 12.0;

/// Fraction of a square the rook must be dragged towards an arm for it to activate.
const _kDragActivationRatio = 0.45;

/// Smaller fraction of a square used to guess which arm the drag is heading to, so the other
/// arms can dim before the destination is committed.
const _kDragHintRatio = 0.08;

/// Fraction of a square the rook must travel towards Play before the drag moves to the second
/// level (the quick matches), without lifting a finger.
const _kStageAdvanceRatio = 0.92;

/// Fraction of a square at which the quick matches begin to appear while sliding towards Play.
const _kQuickRevealStart = 0.5;

/// Fraction of a square to slide back towards the centre before leaving the quick matches.
///
/// Kept at half a square: any further and the second level feels sticky to escape.
const _kBackRatio = 0.5;

/// Board square size, as a fraction of the available width / height.
const _kCellWidthRatio = 0.27;
const _kCellHeightRatio = 0.17;

/// Symbol sizes are fixed, so shrinking the squares only tightens the surrounding boxes.
const _kRookSize = 66.0;
const _kArmIconSize = 30.0;
const _kArmLabelSize = 10.5;
const _kArmLabelSpacing = 1.5;

/// Gap between tiles, and their corner radius.
const _kTileGap = 4.0;
const _kTileRadius = 5.0;

/// Frosted glass: backdrop blur and white tint of the tiles.
const _kGlassBlur = 14.0;
const _kGlassTint = 0.13;

/// Blur applied to arms that are not the drag target, at full dim.
const _kArmBlurSigma = 4.0;

/// Colour a square flashes with after the rook lands on it, like a last-move square.
const _kLandedColor = Color(0x809cc700);

/// The icon for each arm. Swap here to change the whole set.
const _kArmIcons = <CrossMenuAction, IconData>{
  // Chess glyphs from the app's own icon font, so the set stays uniform.
  CrossMenuAction.play: LichessIcons.chess_pawn,
  CrossMenuAction.puzzles: LichessIcons.chess_knight,
  CrossMenuAction.learn: LichessIcons.chess_bishop,
  CrossMenuAction.watch: LichessIcons.chess_queen,
};

/// Home screen built around a rook on a cross-shaped board.
///
/// The rook starts on the centre square. It can be moved in two ways:
///
/// - tap an arm: the rook slides onto it and opens that destination;
/// - drag the rook: it follows the pointer, locked to either the horizontal or the vertical axis
///   (whichever the gesture started along). Legal-move dots appear on the four arms, the other
///   arms dim and blur with distance, and releasing over an arm lands the rook there before
///   opening that destination.
///
/// Destinations are mapped in [kCrossMenuEntries].
class const CrossMenuScreen({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<CrossMenuScreen> createState() => _CrossMenuScreenState();
}

class _CrossMenuScreenState() extends ConsumerState<CrossMenuScreen> {
  late final CrossMenuController _controller;

  /// Total pointer travel since the drag started, before axis locking.
  Offset _panTotal = Offset.zero;

  /// Offset of the rook from the centre while dragging or landing, in logical pixels.
  ///
  /// Always zero along the unlocked axis, which is what locks the movement to one axis.
  Offset _dragOffset = Offset.zero;

  /// Axis the current drag is locked to, or null when no drag is in progress.
  Axis? _dragAxis;

  /// Recent rook offsets, newest first, used to paint the motion trail.
  final List<Offset> _trail = [];

  /// 0 while the rook moves around the cross, 1 while it is picking a quick match next to Play.
  int _stage = 0;

  /// Set while the drag is on its way back from Play, so it does not re-enter the second level
  /// on the next frame (which would pin the rook to Play).
  bool _returningHome = false;

  /// The arm the rook landed on, briefly highlighted before navigating.
  CrossDirection? _landed;

  /// Whether the rook is snapping back or landing, which uses a springy curve.
  bool _springBack = false;

  bool get _isDragging => _dragAxis != null;

  @override
  void initState() {
    super.initState();
    _controller = CrossMenuController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate(CrossMenuEntry entry, {bool fromDrag = false}) async {
    if (!fromDrag) {
      // Ignore taps while the rook is already moving.
      if (!_controller.moveTo(entry.direction)) return;
      await Future<void>.delayed(_controller.moveDuration);
      if (!mounted) return;
    }

    switch (entry.action) {
      case CrossMenuAction.play:
        showAdaptiveBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          builder: (_) => PlayBottomSheet(navigator: Navigator.of(context)),
        );
      case CrossMenuAction.puzzles:
        ref.read(currentBottomTabProvider.notifier).state = BottomTab.puzzles;
      case CrossMenuAction.learn:
        ref.read(currentBottomTabProvider.notifier).state = BottomTab.learn;
      case CrossMenuAction.watch:
        ref.read(currentBottomTabProvider.notifier).state = BottomTab.watch;
    }

    _controller.reset();
  }

  void _onPanStart(DragStartDetails details) {
    _panTotal = Offset.zero;
    _trail.clear();
    HapticFeedback.selectionClick();
    setState(() {
      _dragAxis = null;
      _dragOffset = Offset.zero;
      _landed = null;
      _springBack = false;
      _stage = 0;
      _returningHome = false;
    });
  }

  void _onPanUpdate(DragUpdateDetails details, double cellSize) {
    _panTotal += details.delta;

    // Second level: vertical movement picks a quick match, sliding back returns to the cross.
    if (_stage == 1) {
      if (-_panTotal.dx >= cellSize * _kBackRatio) {
        // Back out to the first level, with the rook on Play; continuing left walks it home.
        setState(() {
          _stage = 0;
          _returningHome = true;
          _dragAxis = Axis.horizontal;
          _panTotal = Offset(cellSize, 0);
          _dragOffset = Offset(cellSize, 0);
          _trail.clear();
        });
        HapticFeedback.selectionClick();
        return;
      }
      setState(() {
        final dy = _panTotal.dy.clamp(-cellSize, cellSize);
        _dragOffset = Offset(cellSize, dy);
        _recordTrail(cellSize);
      });
      return;
    }

    // First level: lock to the axis the gesture started along.
    var axis = _dragAxis;
    if (axis == null && max(_panTotal.dx.abs(), _panTotal.dy.abs()) >= _kDragAxisLockThreshold) {
      axis = _panTotal.dx.abs() >= _panTotal.dy.abs() ? Axis.horizontal : Axis.vertical;
    }
    if (axis == null) return;

    // Sliding all the way onto Play hands the same gesture over to the quick matches, so the
    // second level can be reached without lifting a finger.
    if (!_returningHome &&
        axis == Axis.horizontal &&
        _panTotal.dx >= cellSize * _kStageAdvanceRatio) {
      setState(() {
        _stage = 1;
        _dragAxis = Axis.vertical;
        _panTotal = Offset.zero;
        _dragOffset = Offset(cellSize, 0);
        _trail.clear();
      });
      HapticFeedback.selectionClick();
      return;
    }

    setState(() {
      _dragAxis = axis;
      final travel = axis == Axis.horizontal ? _panTotal.dx : _panTotal.dy;
      final clamped = travel.clamp(-cellSize, cellSize);
      _dragOffset = axis == Axis.horizontal ? Offset(clamped, 0.0) : Offset(0.0, clamped);
      if (_dragOffset.dx.abs() < cellSize * 0.5) _returningHome = false;
      _recordTrail(cellSize);
    });
  }

  void _recordTrail(double cellSize) {
    if (_trail.isEmpty || (_trail.first - _dragOffset).distance > cellSize * 0.12) {
      _trail.insert(0, _dragOffset);
      if (_trail.length > 3) _trail.removeLast();
    }
  }

  Future<void> _onPanEnd(double cellSize) async {
    final stage = _stage;
    final axis = _dragAxis;
    final offset = _dragOffset;

    setState(() {
      _dragAxis = null;
      _panTotal = Offset.zero;
      _trail.clear();
      _springBack = true;
      _stage = 0;
      _returningHome = false;
    });

    if (stage == 1) {
      await _finishQuickMatch(offset.dy, cellSize);
      return;
    }

    final direction = _directionFor(axis, offset, cellSize);
    if (direction == null) {
      // Released too close to the centre: spring back.
      setState(() => _dragOffset = Offset.zero);
      return;
    }

    // Play keeps its default behaviour: landing on it opens the full play sheet.
    final (col, row) = direction.gridOffset;
    setState(() {
      _dragOffset = Offset(col * cellSize, row * cellSize);
      _landed = direction;
    });
    HapticFeedback.lightImpact();

    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;

    await _activate(
      kCrossMenuEntries.firstWhere((entry) => entry.direction == direction),
      fromDrag: true,
    );
    if (!mounted) return;
    setState(() {
      _landed = null;
      _dragOffset = Offset.zero;
      _springBack = false;
    });
  }

  static CrossDirection _directionOf(QuickMatchSide side) =>
      side == QuickMatchSide.up ? CrossDirection.up : CrossDirection.down;

  /// Tapping a quick tile configures it on first run, otherwise starts it.
  Future<void> _onQuickTileTapped(QuickMatchSide side) async {
    final prefs = ref.read(quickMatchPreferencesProvider);
    if (!prefs.isConfigured) {
      await showQuickMatchesSheet(context);
      if (!mounted) return;
      await ref.read(quickMatchPreferencesProvider.notifier).markConfigured();
      return;
    }
    await _startQuickMatch(prefs.resolve(side));
  }

  /// Ends a second-level drag: a quick match if the rook is over one, the play sheet otherwise.
  Future<void> _finishQuickMatch(double dy, double cellSize) async {
    final threshold = cellSize * _kDragActivationRatio;

    if (dy.abs() >= threshold) {
      final side = dy < 0 ? QuickMatchSide.up : QuickMatchSide.down;
      final prefs = ref.read(quickMatchPreferencesProvider);

      if (!prefs.isConfigured) {
        // First run: the tiles teach themselves rather than starting an unknown game.
        setState(() => _dragOffset = Offset.zero);
        await showQuickMatchesSheet(context);
        if (!mounted) return;
        await ref.read(quickMatchPreferencesProvider.notifier).markConfigured();
        return;
      }

      final timeControl = prefs.resolve(side);
      setState(() => _dragOffset = Offset(cellSize, _directionOf(side).gridOffset.$2 * cellSize));
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      await _startQuickMatch(timeControl);
      return;
    }

    // Released on Play itself: default play behaviour.
    setState(() => _dragOffset = Offset.zero);
    await _activate(
      kCrossMenuEntries.firstWhere((entry) => entry.direction == CrossDirection.right),
      fromDrag: true,
    );
  }

  /// Starts a quick match straight away, skipping the play sheet.
  Future<void> _startQuickMatch(TimeIncrement timeControl) async {
    await ref.read(quickMatchPreferencesProvider.notifier).recordPlayed(timeControl);
    final authUser = ref.read(authControllerProvider);
    if (!mounted) return;
    Navigator.of(context).pushHidingTabBar(
      GameScreen.buildRoute(source: LobbySource(GameSeek.fastPairing(timeControl, authUser))),
    );
    if (!mounted) return;
    _controller.reset();
    setState(() {
      _dragOffset = Offset.zero;
      _springBack = false;
    });
  }

  void _onPanCancel() {
    setState(() {
      _dragAxis = null;
      _dragOffset = Offset.zero;
      _panTotal = Offset.zero;
      _trail.clear();
      _springBack = true;
    });
  }

  /// The arm the drag is heading to, as soon as the rook has moved a little.
  CrossDirection? _dragHint(double cellSize) {
    final threshold = cellSize * _kDragHintRatio;
    return switch (_dragAxis) {
      Axis.horizontal when _dragOffset.dx >= threshold => CrossDirection.right,
      Axis.horizontal when _dragOffset.dx <= -threshold => CrossDirection.left,
      Axis.vertical when _dragOffset.dy >= threshold => CrossDirection.down,
      Axis.vertical when _dragOffset.dy <= -threshold => CrossDirection.up,
      _ => null,
    };
  }

  /// The arm the rook would commit to, if released now.
  CrossDirection? _dragTarget(double cellSize) => _directionFor(_dragAxis, _dragOffset, cellSize);

  CrossDirection? _directionFor(Axis? axis, Offset offset, double cellSize) {
    if (axis == null) return null;
    final threshold = cellSize * _kDragActivationRatio;
    return switch (axis) {
      Axis.horizontal when offset.dx >= threshold => CrossDirection.right,
      Axis.horizontal when offset.dx <= -threshold => CrossDirection.left,
      Axis.vertical when offset.dy >= threshold => CrossDirection.down,
      Axis.vertical when offset.dy <= -threshold => CrossDirection.up,
      _ => null,
    };
  }

  /// How far the rook has been dragged towards the current target, from 0 to 1.
  ///
  /// Drives the progressive dimming and blurring of the other arms: they recede as the rook
  /// travels, and are fully dimmed once the drag reaches the point where releasing would commit.
  double _dimProgress(double cellSize) {
    if (_dragAxis == null) return 0;
    final distance = _dragAxis == Axis.horizontal ? _dragOffset.dx.abs() : _dragOffset.dy.abs();
    return (distance / (cellSize * _kDragActivationRatio)).clamp(0.0, 1.0);
  }

  /// How far the quick matches are revealed, 0 to 1, while the rook slides towards Play.
  double _quickReveal(double cellSize) {
    if (_stage == 1) return 1;
    if (_dragAxis != Axis.horizontal || _dragOffset.dx <= 0) return 0;
    final progress = _dragOffset.dx / cellSize;
    return ((progress - _kQuickRevealStart) / (_kStageAdvanceRatio - _kQuickRevealStart)).clamp(
      0.0,
      1.0,
    );
  }

  /// The quick match the rook is currently over, once the second level is active.
  CrossDirection? _quickTarget(double cellSize) {
    if (_stage != 1) return null;
    final threshold = cellSize * _kDragActivationRatio;
    if (_dragOffset.dy <= -threshold) return CrossDirection.up;
    if (_dragOffset.dy >= threshold) return CrossDirection.down;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final quickPrefs = ref.watch(quickMatchPreferencesProvider);

    return Stack(
      children: [
        const Positioned.fill(child: _HomeBackdrop()),
        SafeArea(
          // A Material ancestor provides the default text style; without it, text inherits
          // MaterialApp's fallback style, which is underlined.
          child: Material(
            type: MaterialType.transparency,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellSize = min(
                  constraints.maxWidth * _kCellWidthRatio,
                  constraints.maxHeight * _kCellHeightRatio,
                );
                final crossSize = cellSize * 3;

                // The whole screen is draggable: a swipe from anywhere moves the rook.
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: (details) => _onPanUpdate(details, cellSize),
                  onPanEnd: (_) => _onPanEnd(cellSize),
                  onPanCancel: _onPanCancel,
                  child: Center(
                    child: SizedBox(
                      width: crossSize,
                      height: crossSize,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final active = _controller.activeDirection;
                          // While Play is focused the arms are no longer targets: the quick
                          // matches above and below it are.
                          final dragHint = _stage == 1 ? null : _dragHint(cellSize);
                          final dragTarget = _stage == 1 ? null : _dragTarget(cellSize);
                          final dimProgress = _stage == 1 ? 0.0 : _dimProgress(cellSize);
                          final quickTarget = _quickTarget(cellSize);
                          final quickReveal = _quickReveal(cellSize);
                          final (rookCol, rookRow) = active?.gridOffset ?? (0, 0);

                          // White on the dark centre square, dark once over a white arm.
                          final rookOnArm = active != null || _dragOffset.distance > cellSize * 0.5;
                          final rookColor = rookOnArm ? const Color(0xff1a1a20) : Colors.white;
                          final rimColor = rookOnArm ? Colors.white : const Color(0xff1a1a20);

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // The pane the rook rests on.
                              Positioned(
                                left: cellSize,
                                top: cellSize,
                                width: cellSize,
                                height: cellSize,
                                child: const _CenterPane(),
                              ),

                              // Tiles.
                              for (final entry in kCrossMenuEntries)
                                Positioned(
                                  left: (entry.direction.gridOffset.$1 + 1) * cellSize,
                                  top: (entry.direction.gridOffset.$2 + 1) * cellSize,
                                  width: cellSize,
                                  height: cellSize,
                                  child: _ArmTile(
                                    entry: entry,
                                    icon: _kArmIcons[entry.action]!,
                                    isActive:
                                        active == entry.direction || dragTarget == entry.direction,
                                    isLanded: _landed == entry.direction,
                                    dimFactor: _stage == 1
                                        ? (entry.direction == CrossDirection.right ? 0.0 : 1.0)
                                        : dragHint != null && dragHint != entry.direction
                                        ? dimProgress
                                        : 0.0,
                                    animate: !_isDragging,
                                    colorScheme: colorScheme,
                                    onTap: _controller.isMoving || _isDragging
                                        ? null
                                        : () => _activate(entry),
                                    // Long-pressing Play configures the quick matches.
                                    onLongPress: entry.direction == CrossDirection.right
                                        ? () => showQuickMatchesSheet(context)
                                        : null,
                                  ),
                                ),

                              // Quick matches, revealed above and below Play once it is focused.
                              for (final side in QuickMatchSide.values)
                                Positioned(
                                  left: 2 * cellSize,
                                  top: (side == QuickMatchSide.up ? 0 : 2) * cellSize,
                                  width: cellSize,
                                  height: cellSize,
                                  child: IgnorePointer(
                                    ignoring: quickReveal < 0.9,
                                    child: AnimatedOpacity(
                                      duration: const Duration(milliseconds: 180),
                                      opacity: quickReveal,
                                      child: AnimatedScale(
                                        duration: const Duration(milliseconds: 180),
                                        curve: Curves.easeOutBack,
                                        scale: 0.75 + 0.25 * quickReveal,
                                        child: _QuickMatchTile(
                                          side: side,
                                          timeControl: quickPrefs.resolve(side),
                                          isSetUp: !quickPrefs.isConfigured,
                                          isActive: quickTarget == _directionOf(side),
                                          colorScheme: colorScheme,
                                          onTap: () => _onQuickTileTapped(side),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // Legal move dots, lichess style, pushed towards the outer edge so
                              // they do not sit on top of the labels.
                              for (final entry in kCrossMenuEntries)
                                Positioned(
                                  left: (entry.direction.gridOffset.$1 + 1) * cellSize,
                                  top: (entry.direction.gridOffset.$2 + 1) * cellSize,
                                  width: cellSize,
                                  height: cellSize,
                                  child: IgnorePointer(
                                    child: Center(
                                      child: FractionalTranslation(
                                        translation: Offset(
                                          entry.direction.gridOffset.$1 * 0.36,
                                          entry.direction.gridOffset.$2 * 0.36,
                                        ),
                                        child: AnimatedOpacity(
                                          duration: const Duration(milliseconds: 120),
                                          opacity: _isDragging && _stage == 0 ? 1.0 : 0.0,
                                          child: Container(
                                            width: cellSize * 0.15,
                                            height: cellSize * 0.15,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white.withValues(alpha: 0.55),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // Motion trail.
                              for (final (index, offset) in _trail.indexed)
                                Positioned(
                                  left: (rookCol + 1) * cellSize + offset.dx,
                                  top: (rookRow + 1) * cellSize + offset.dy,
                                  width: cellSize,
                                  height: cellSize,
                                  child: IgnorePointer(
                                    child: Center(
                                      child: Opacity(
                                        opacity: 0.16 - index * 0.04,
                                        child: RookPiece(
                                          size: _kRookSize * (0.94 - index * 0.04),
                                          color: rookColor,
                                          rimColor: rimColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // The rook.
                              AnimatedPositioned(
                                duration: _isDragging ? Duration.zero : _controller.moveDuration,
                                curve: _springBack ? Curves.easeOutBack : Curves.easeInOutCubic,
                                left: (rookCol + 1) * cellSize + _dragOffset.dx,
                                top: (rookRow + 1) * cellSize + _dragOffset.dy,
                                width: cellSize,
                                height: cellSize,
                                child: IgnorePointer(
                                  child: Center(
                                    child: AnimatedScale(
                                      duration: const Duration(milliseconds: 120),
                                      curve: Curves.easeOut,
                                      scale: _isDragging || active != null ? 1.08 : 1.0,
                                      child: RookPiece(
                                        size: _kRookSize,
                                        color: rookColor,
                                        rimColor: rimColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Darkens the app background behind the cross and adds a vignette, with a very slow drift.
///
/// Cheap by construction: one gradient repainted behind a [RepaintBoundary], animated over 45 s.
class const _HomeBackdrop() extends StatefulWidget {
  @override
  State<_HomeBackdrop> createState() => _HomeBackdropState();
}

class _HomeBackdropState() extends State<_HomeBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 45))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.15 + t * 0.3, -0.25 + t * 0.2),
                      radius: 1.15,
                      colors: const [Color(0x00000000), Color(0xCC000000)],
                      stops: const [0.3, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The centre pane: darker glass, so the white rook reads against it.
class const _CenterPane() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_kTileRadius);
    return Padding(
      padding: const EdgeInsets.all(_kTileGap / 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14.0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _kGlassBlur, sigmaY: _kGlassBlur),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
                const Positioned.fill(
                  child: CustomPaint(
                    painter: _GlassBorderPainter(
                      radius: _kTileRadius,
                      highlight: Colors.white,
                      opacity: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One arm of the cross: a frosted glass pane over the background.
class const _ArmTile({
  required final CrossMenuEntry entry,
  required final IconData icon,
  required final bool isActive,
  required final bool isLanded,

  /// 0 = untouched, 1 = fully dimmed/blurred.
  required final double dimFactor,

  /// Whether changes should animate; during a drag they must track the pointer immediately.
  required final bool animate,
  required final ColorScheme colorScheme,
  required final VoidCallback? onTap,
  required final VoidCallback? onLongPress,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final duration = animate ? const Duration(milliseconds: 150) : Duration.zero;
    final blurSigma = _kArmBlurSigma * dimFactor;

    Widget content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: _kArmIconSize, color: Colors.white),
        const SizedBox(height: 6.0),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            entry.label.toUpperCase(),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: _kArmLabelSize,
              fontWeight: FontWeight.w500,
              letterSpacing: _kArmLabelSpacing,
            ),
          ),
        ),
      ],
    );

    if (blurSigma > 0.05) {
      content = ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: content,
        ),
      );
    }

    final radius = BorderRadius.circular(_kTileRadius);

    return Semantics(
      button: true,
      label: entry.label,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Half the gap per tile, so neighbours end up one gap apart.
          padding: const EdgeInsets.all(_kTileGap / 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35 - 0.2 * dimFactor),
                  blurRadius: 14.0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: _kGlassBlur, sigmaY: _kGlassBlur),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: Colors.white.withValues(
                        alpha: lerpDouble(_kGlassTint, 0.07, dimFactor),
                      ),
                    ),
                    if (isLanded) ColoredBox(color: _kLandedColor.withValues(alpha: 0.5)),
                    if (dimFactor > 0)
                      ColoredBox(color: Colors.black.withValues(alpha: 0.5 * dimFactor)),
                    if (isActive) ColoredBox(color: colorScheme.primary.withValues(alpha: 0.18)),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: AnimatedOpacity(
                        duration: duration,
                        opacity: lerpDouble(1.0, 0.5, dimFactor)!,
                        child: content,
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GlassBorderPainter(
                          radius: _kTileRadius,
                          highlight: isActive ? colorScheme.primary : Colors.white,
                          opacity: isActive ? 1.0 : 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quick match tile shown above or below the Play arm.
class const _QuickMatchTile({
  required final QuickMatchSide side,
  required final TimeIncrement timeControl,
  required final bool isSetUp,
  required final bool isActive,
  required final ColorScheme colorScheme,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_kTileRadius);
    final speedLabel = _speedLabel(timeControl.speed);

    return Semantics(
      button: true,
      label: isSetUp ? 'Set up quick match' : '${timeControl.display} $speedLabel',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(_kTileGap / 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14.0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: _kGlassBlur, sigmaY: _kGlassBlur),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: Colors.white.withValues(alpha: _kGlassTint)),
                    if (isActive) ColoredBox(color: colorScheme.primary.withValues(alpha: 0.22)),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: isSetUp
                            ? [
                                const Icon(Icons.tune, size: 20.0, color: Colors.white70),
                                const SizedBox(height: 4.0),
                                const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'SET UP',
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: _kArmLabelSpacing,
                                    ),
                                  ),
                                ),
                              ]
                            : [
                                Text(
                                  timeControl.display,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17.0,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 3.0),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    speedLabel,
                                    maxLines: 1,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: _kArmLabelSpacing,
                                    ),
                                  ),
                                ),
                              ],
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GlassBorderPainter(
                          radius: _kTileRadius,
                          highlight: isActive ? colorScheme.primary : Colors.white,
                          opacity: isActive ? 1.0 : 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 1 px border that is brighter along the top edge, like light catching a glass edge.
class const _GlassBorderPainter({
  required final double radius,
  required final Color highlight,
  required final double opacity,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          highlight.withValues(alpha: 0.55 * opacity),
          highlight.withValues(alpha: 0.08 * opacity),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GlassBorderPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.highlight != highlight ||
      oldDelegate.opacity != opacity;
}

/// Short, upper-case speed name for the quick match tiles.
///
/// Deliberately local rather than localised: the home screen is full of hard-coded English and
/// this keeps the tile renderable without an [AppLocalizations] delegate (e.g. in widget tests).
String _speedLabel(Speed speed) => switch (speed) {
  Speed.ultraBullet => 'ULTRA BULLET',
  Speed.bullet => 'BULLET',
  Speed.blitz => 'BLITZ',
  Speed.rapid => 'RAPID',
  Speed.classical => 'CLASSICAL',
  Speed.correspondence => 'CORRESPONDENCE',
};
