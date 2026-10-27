import 'dart:math';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/analysis/analysis_controller.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_controller.dart';
import 'package:lichess_mobile/src/model/game/game_status.dart';
import 'package:lichess_mobile/src/model/game/over_the_board_game.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/tournament/tournament_controller.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/game/status_l10n.dart';
import 'package:lichess_mobile/src/view/settings/settings_screen.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/glass_modal.dart';
import 'package:material_ui/material_ui.dart';

class const GameResultDialog({
  required final GameFullId id,

  /// Callback to load a new opponent.
  required final void Function(PlayableGame game) onNewOpponentCallback,

  /// Callback to navigate back to the tournament of the game, once the dialog is closed.
  required final void Function(TournamentId tournamentId) onBackToTournamentCallback,

  /// Callback to open the analysis of the game, once the dialog is closed.
  ///
  /// It pushes with the game screen's context: the dialog is on the root navigator, the game screen
  /// may be in a tab navigator.
  required final void Function(AnalysisOptions options) onAnalysisCallback,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<GameResultDialog> createState() => _GameResultDialogState();
}

class _GameResultDialogState()
    extends ConsumerState<GameResultDialog>
    with SingleTickerProviderStateMixin {
  /// How long the actions take to fade in. They accept taps once this completes, which is the
  /// misclick guard the dialog had before, folded into the animation so there is no dead beat.
  static const _entranceDuration = Duration(milliseconds: 350);

  late final AnimationController _entrance;
  bool _motionChecked = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: _entranceDuration);
    // Start after the first frame: a slow first frame could otherwise run the whole entrance
    // before it was ever painted, so the actions appeared fully and then animated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entrance.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionChecked) return;
    _motionChecked = true;
    // Respect the platform's reduce-motion setting: appear armed immediately.
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1.0;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Closes the dialog (and anything else popup-shaped above the game screen).
  void _closePopups() {
    Navigator.of(context).popUntil((route) => route is! PopupRoute);
  }

  /// Leaves the game and opens the app settings.
  void _openSettings() {
    final navigator = Navigator.of(context);
    _closePopups();
    navigator.push(SettingsScreen.buildRoute());
  }

  /// Leaves the game and returns to the home tab.
  void _backToHome() {
    final tabNotifier = ref.read(currentBottomTabProvider.notifier);
    final homeNavigator = homeNavigatorKey.currentState;
    Navigator.of(context).popUntil((route) => route.isFirst);
    tabNotifier.state = BottomTab.home;
    homeNavigator?.popUntil((route) => route.isFirst);
  }

  /// The rematch button action, or null to disable it. A socket offer if the
  /// opponent is online, otherwise a challenge for offline clockless games.
  VoidCallback? _rematchAction(BuildContext context, GameState value) {
    if (value.game.opponent?.offeringRematch == true) {
      return null;
    }
    final ctrlProvider = gameControllerProvider(widget.id);
    if (value.game.opponent?.onGame == true) {
      return () {
        ref.read(ctrlProvider.notifier).proposeOrAcceptRematch();
      };
    }
    if (value.game.clock == null &&
        value.game.me?.user != null &&
        value.game.opponent?.user != null) {
      return () async {
        try {
          await ref.read(ctrlProvider.notifier).challengeRematch();
        } catch (_) {
          if (context.mounted) {
            showSnackBar(context, 'Could not send the rematch challenge', type: SnackBarType.error);
          }
        }
      };
    }
    return null;
  }

  void _backToTournament(TournamentId tournamentId) {
    Navigator.of(context).popUntil((route) => route is! PopupRoute);
    widget.onBackToTournamentCallback(tournamentId);
  }

  @override
  Widget build(BuildContext context) {
    final ctrlProvider = gameControllerProvider(widget.id);

    return switch (ref.watch(ctrlProvider)) {
      AsyncError() => const Center(child: Text('Could not load game')),
      AsyncData(:final value) => _ResultDialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: GameResult(game: value.game),
            ),
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) => Opacity(
                key: const ValueKey('game-result-actions'),
                opacity: 0.55 + 0.45 * _entrance.value,
                child: Transform.translate(
                  offset: Offset(0.0, 6.0 * (1 - _entrance.value)),
                  child: child,
                ),
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 400),
                      firstCurve: Curves.easeOutExpo,
                      secondCurve: Curves.easeInExpo,
                      sizeCurve: Curves.easeInOut,
                      firstChild: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (value.game.me?.offeringRematch == true ||
                              value.correspondenceRematchId != null) ...[
                            Flexible(
                              flex: 3,
                              child: Text(
                                maxLines: 2,
                                context.l10n.rematchOfferSent,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Spacer(),
                            IconButton.outlined(
                              onPressed: () async {
                                if (value.game.me?.offeringRematch == true) {
                                  ref.read(ctrlProvider.notifier).declineRematch();
                                } else {
                                  try {
                                    await ref.read(ctrlProvider.notifier).cancelRematchChallenge();
                                  } catch (_) {
                                    if (context.mounted) {
                                      showSnackBar(
                                        context,
                                        'Could not cancel the rematch challenge',
                                        type: SnackBarType.error,
                                      );
                                    }
                                  }
                                }
                              },
                              tooltip: context.l10n.cancelRematchOffer,
                              icon: const Icon(Icons.cancel),
                            ),
                          ] else if (value.canOfferRematch)
                            Expanded(
                              child: FilledButton(
                                onPressed: _rematchAction(context, value),
                                child: Text(context.l10n.rematch),
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                      secondChild: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 15.0),
                            child: Text(
                              context.l10n.yourOpponentWantsToPlayANewGameWithYou,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 15.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                IconButton.filled(
                                  icon: const Icon(Icons.check),
                                  style: FilledButton.styleFrom(
                                    foregroundColor: ColorScheme.of(context).onPrimary,
                                    backgroundColor: ColorScheme.of(context).primary,
                                  ),
                                  tooltip: context.l10n.accept,
                                  onPressed: () {
                                    ref.read(ctrlProvider.notifier).proposeOrAcceptRematch();
                                  },
                                ),
                                IconButton.filled(
                                  icon: const Icon(Icons.close),
                                  style: FilledButton.styleFrom(
                                    foregroundColor: ColorScheme.of(context).onError,
                                    backgroundColor: ColorScheme.of(context).error,
                                  ),
                                  tooltip: context.l10n.decline,
                                  onPressed: () {
                                    ref.read(ctrlProvider.notifier).declineRematch();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      crossFadeState: value.game.opponent?.offeringRematch ?? false
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                    ),
                    if (value.canGetNewOpponent)
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(context).popUntil((route) => route is! PopupRoute);
                          widget.onNewOpponentCallback(value.game);
                        },
                        child: Text(context.l10n.newOpponent, textAlign: TextAlign.center),
                      ),
                    if (value.tournament?.isOngoing == true) ...[
                      FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _backToTournament(value.tournament!.id),
                        label: Text(context.l10n.backToTournament, textAlign: TextAlign.center),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.pause),
                        onPressed: () {
                          // Pause the tournament
                          ref
                              .read(tournamentControllerProvider(value.tournament!.id).notifier)
                              .joinOrPause();
                          _backToTournament(value.tournament!.id);
                        },
                        label: Text(context.l10n.pause, textAlign: TextAlign.center),
                      ),
                    ],
                    if (value.game.userAnalysable)
                      FilledButton.tonal(
                        onPressed: () {
                          Navigator.of(context).popUntil((route) => route is! PopupRoute);
                          widget.onAnalysisCallback(value.analysisOptions);
                        },
                        child: Text(context.l10n.analysis, textAlign: TextAlign.center),
                      ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.settings_outlined, size: 18.0),
                      onPressed: _openSettings,
                      label: const Text('Settings', textAlign: TextAlign.center),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.home_outlined, size: 18.0),
                      onPressed: _backToHome,
                      label: const Text('Back to home', textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _ => const Center(child: CircularProgressIndicator.adaptive()),
    };
  }
}

class const OverTheBoardGameResultDialog({
  super.key,
  required final OverTheBoardGame game,
  required final void Function() onRematch,

  /// Callback to open the analysis of the game, once the dialog is closed.
  ///
  /// It pushes with the game screen's context: the dialog is on the root navigator, the game screen
  /// may be in a tab navigator.
  required final void Function(AnalysisOptions options) onAnalysis,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GameResult(game: game),
        FilledButton(
          onPressed: onRematch,
          child: Text(context.l10n.rematch, textAlign: TextAlign.center),
        ),
        FilledButton.tonal(
          onPressed: () {
            Navigator.pop(context);
            onAnalysis(
              AnalysisOptions.pgn(
                id: const StringId('otb_finished_game_analysis'),
                orientation: Side.white,
                pgn: game.makePgn(),
                isComputerAnalysisAllowed: true,
                variant: game.meta.variant,
              ),
            );
          },
          child: Text(context.l10n.analysis, textAlign: TextAlign.center),
        ),
      ],
    );

    return _ResultDialog(child: content);
  }
}

class const GameResult({required final BaseGame game, super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final showWinner = game.winner != null
        ? ' • ${game.winner == Side.white ? context.l10n.whiteIsVictorious : context.l10n.blackIsVictorious}'
        : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (game.status.value >= GameStatus.mate.value)
          Text(
            game.winner == null
                ? '½-½'
                : game.winner == Side.white
                ? '1-0'
                : '0-1',
            style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 6.0),
        Text(
          '${gameStatusL10n(context, variant: game.meta.variant, status: game.status, lastPosition: game.lastPosition, winner: game.winner, isThreefoldRepetition: game.isThreefoldRepetition)}$showWinner',
          style: const TextStyle(fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class const _ResultDialog({required final Widget child}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // Shown over the board, which the glass would let show through too much.
      return GlassDialogFrame(tinted: true, child: child);
    }
    final screenWidth = MediaQuery.widthOf(context);
    final paddedContent = Padding(padding: const EdgeInsets.all(16.0), child: child);
    final sizedContent = SizedBox(
      width: min(screenWidth, kMaterialPopupMenuMaxWidth),
      child: paddedContent,
    );
    return Dialog(child: sizedContent);
  }
}
