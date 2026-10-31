import 'package:chessground/chessground.dart' show readFen;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/speed.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/game_controller.dart';
import 'package:lichess_mobile/src/model/game/game_preferences.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/lobby/game_setup_preferences.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/service/create_game_service.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/immersive_mode.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/game/exported_game_title.dart';
import 'package:lichess_mobile/src/view/game/game_body.dart';
import 'package:lichess_mobile/src/view/game/game_common_widgets.dart';
import 'package:lichess_mobile/src/view/game/game_loading_board.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/game/match_intro.dart';
import 'package:lichess_mobile/src/view/game/watcher_list_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/android_gesture_exclusion.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/misc.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_context_menu_button.dart';
import 'package:material_ui/material_ui.dart';

/// Screen to play a game, or to show a challenge or to show current user's past games.
///
/// The screen can be opened in three ways:
/// - From the lobby, to play a game with a random opponent: using [LobbySource].
/// - From a challenge, to accept or decline a challenge: using a [UserChallengeSource].
/// - From an existing game: using [ExistingGameSource].
///
/// The screen will show a loading board while the game is being created.
class const GameScreen({
  required final GameScreenSource source,
  final LoadingParam? loadingPosition,

  /// The date of the last move played in the game. If null, the game is in progress.
  final DateTime? lastMoveAt,
  super.key,
}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute({
    required GameScreenSource source,
    LoadingParam? loadingPosition,
    DateTime? lastMoveAt,
  }) {
    return buildScreenRoute(
      screen: GameScreen(source: source, loadingPosition: loadingPosition, lastMoveAt: lastMoveAt),
    );
  }

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState() extends ConsumerState<GameScreen> {
  final _whiteClockKey = GlobalKey(debugLabel: 'whiteClockOnGameScreen');
  final _blackClockKey = GlobalKey(debugLabel: 'blackClockOnGameScreen');
  final _boardKey = GlobalKey(debugLabel: 'boardOnGameScreen');
  AppLifecycleListener? _appLifecycleListener;

  /// The game whose match intro is waiting for it to load: found by this screen's search, or loaded
  /// from the game on screen (a rematch). Cleared as soon as the game board starts the intro, so it
  /// plays once.
  _PendingIntro? _pendingIntro;

  /// While a game loaded from the one on screen (a rematch, a redirect) loads, the game it replaces
  /// stays on screen instead of a loading skeleton.
  GameFullId? _heldGameId;

  /// The board of the game this screen left to search for a new opponent: its pieces are lifted off
  /// the search screen's board.
  MatchIntroBoard? _searchClearing;

  /// Whether the search screen of [source] stays up, with its card saying the game was found, until
  /// the game data is loaded, and then hands over to the game board with the match intro.
  static bool _hasSearchCard(GameScreenSource source) => switch (source) {
    LobbySource() => true,
    UserChallengeSource(:final challengeRequest) => challengeRequest.destUser != null,
    ExistingGameSource() => false,
  };

  @override
  void initState() {
    super.initState();
    // Cancel pending seek when app goes to background to prevent games being created
    // while the user is away from the app.
    _appLifecycleListener = AppLifecycleListener(onPause: _cancelSeek);

    // Queues the intro of each new game, and remembers the board of a game that is being left.
    ref.listenManual<AsyncValue<GameScreenState>>(gameScreenLoaderProvider(widget.source), (
      prev,
      next,
    ) {
      // Only data counts: while searching again ("new opponent") the loading state still carries
      // the previous game.
      final prevGameId = switch (prev) {
        AsyncData(value: GameCreatedState(:final createdGameId)) => createdGameId,
        _ => null,
      };
      switch (next) {
        case AsyncLoading() when prevGameId != null:
          // Leaving a game to search for a new opponent.
          _searchClearing = _boardOf(prevGameId);
        case AsyncData(value: GameCreatedState(:final createdGameId))
            when createdGameId != prevGameId:
          if (prevGameId == null) {
            // Found by a search: a short haptic, and the intro dissolves the search card.
            if (_hasSearchCard(widget.source)) {
              HapticFeedback.mediumImpact();
              _pendingIntro = (gameId: createdGameId, fromSearch: true, clearing: null);
            }
          } else {
            // Loaded from the game on screen. A finished game (a rematch) is cleared off the board
            // before the new one drops in; a game in progress is just replaced.
            final previous = ref.exists(gameControllerProvider(prevGameId))
                ? ref.read(gameControllerProvider(prevGameId)).value
                : null;
            _heldGameId = prevGameId;
            _pendingIntro = (
              gameId: createdGameId,
              fromSearch: false,
              clearing: previous?.game.playable == false ? _boardOf(prevGameId) : null,
            );
          }
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _appLifecycleListener?.dispose();
    super.dispose();
  }

  /// The board of game [id] as it is shown, if the game is loaded and its pieces are visible.
  MatchIntroBoard? _boardOf(GameFullId id) {
    if (!ref.exists(gameControllerProvider(id))) return null;
    final state = ref.read(gameControllerProvider(id)).value;
    if (state == null || ref.read(gamePreferencesProvider).blindfoldMode == true) return null;
    return (
      pieces: readFen(state.currentPosition.fen),
      orientation: variantBoardOrientation(
        variant: state.game.meta.variant,
        youAre: state.game.youAre ?? Side.white,
        isBoardTurned: ref.read(isBoardTurnedProvider),
      ),
    );
  }

  /// Marks the pending intro as played (or skipped), from the build of this screen or of the game
  /// board: the new game has replaced the previous one.
  void _consumeIntro() {
    _pendingIntro = null;
    _heldGameId = null;
    // Rebuild once, so the screen stops watching whether the game data is loaded: it must not
    // rebuild with the game state.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _cancelSeek() async {
    if (!mounted) return;
    final loader = ref.read(gameScreenLoaderProvider(widget.source));
    // Only cancel if we are still seeking
    if (loader is! AsyncLoading<GameScreenState>) {
      return;
    }
    switch (widget.source) {
      case LobbySource():
        await ref.read(createGameServiceProvider).cancelSeek();
      case UserChallengeSource():
        break;
      case ExistingGameSource():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardPreferences = ref.watch(boardPreferencesProvider);

    switch (ref.watch(gameScreenLoaderProvider(widget.source))) {
      case AsyncData(value: SeekCancelledState()):
        return PlatformScaffold(
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          appBar: PlatformAppBar(
            title: switch (widget.source) {
              LobbySource(:final seek) => _GameTitle(_LobbyTitleVariant(seek)),
              _ => null,
            },
          ),
          body: const LoadGameError('The game search was cancelled.', showBottomBar: false),
        );
      case AsyncData(value: ChallengeCancelledState()):
        return PlatformScaffold(
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          appBar: PlatformAppBar(
            title: _GameTitle(
              _ChallengeTitleVariant((widget.source as UserChallengeSource).challengeRequest),
            ),
          ),
          body: const LoadGameError('The challenge was cancelled.', showBottomBar: false),
        );
      case AsyncData(
        value: ChallengeDeclinedState(
          response: ChallengeResponseDeclined(:final challenge, :final declineReason),
        ),
      ):
        return PlatformScaffold(
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          appBar: PlatformAppBar(
            title: _GameTitle(
              _ChallengeTitleVariant((widget.source as UserChallengeSource).challengeRequest),
            ),
          ),
          body: ChallengeDeclinedBoard(
            challenge: challenge,
            declineReason: declineReason != null
                ? declineReason.label(context.l10n)
                : ChallengeDeclineReason.generic.label(context.l10n),
          ),
        );
      case AsyncData(value: GameCreatedState(:final createdGameId)):
        // Keep what was on screen (the search screen, its card saying the game was found, or the
        // finished game) until the new game data exists, instead of flashing a loading skeleton in
        // between. Watching the controller here also starts loading it. Only watched while the game
        // is pending: the screen must not rebuild with the game state.
        final pending = _pendingIntro?.gameId == createdGameId ? _pendingIntro : null;
        final gameReady =
            pending == null ||
            ref.watch(
              gameControllerProvider(createdGameId).select((s) => s.hasValue || s.hasError),
            );
        if (!gameReady && pending.fromSearch) {
          return PlatformScaffold(
            extendBodyBehindAppBar: false,
            resizeToAvoidBottomInset: false,
            appBar: PlatformAppBar(
              leading: const AppBarIndicator(child: SocketPingRatingIcon()),
              title: switch (widget.source) {
                LobbySource(:final seek) => _GameTitle(
                  _LobbyTitleVariant(seek),
                  monitorSocket: true,
                ),
                UserChallengeSource(:final challengeRequest) => _GameTitle(
                  _ChallengeTitleVariant(challengeRequest),
                  monitorSocket: true,
                ),
                ExistingGameSource() => null,
              },
            ),
            body: PopScope(
              canPop: false,
              child: WakelockWidget(
                child: switch (widget.source) {
                  LobbySource(:final seek) => LobbyScreenLoadingContent(
                    seek,
                    () async {},
                    isStarting: true,
                    clearing: _searchClearing,
                  ),
                  UserChallengeSource(:final challengeRequest) => UserChallengeLoadingContent(
                    challengeRequest,
                    () async {},
                    isStarting: true,
                  ),
                  ExistingGameSource() => const SizedBox.shrink(),
                },
              ),
            ),
          );
        }

        // The game shown: the one replaced by a game that is still loading, else the new one.
        final gameId = !gameReady && _heldGameId != null ? _heldGameId! : createdGameId;

        // Until the provider resolves (a frame), read a game that is already loaded, so the leading
        // icon and the back-button guard don't drop for a frame when the game appears. Read, not
        // watched: the screen must not rebuild with the game state.
        final isRealTimePlayingGame =
            ref.watch(_isRealTimePlayableGameProvider(gameId).select((s) => s.value)) ??
            switch (ref.read(gameControllerProvider(gameId)).value) {
              final state? => state.game.meta.speed != Speed.correspondence && state.game.playable,
              null => false,
            };

        // The intro plays from a search, or from a finished game it clears off the board. Not with
        // reduce-motion on, nor between games in progress: the new game then just replaces the
        // previous screen.
        final playIntro =
            pending != null &&
            gameReady &&
            !MediaQuery.disableAnimationsOf(context) &&
            (pending.fromSearch || pending.clearing != null);
        if (pending != null && gameReady && !playIntro) _consumeIntro();

        final intro = playIntro
            ? MatchIntro(
                // The search card as the search screen last showed it, for the board to dissolve.
                card: pending.fromSearch
                    ? switch (widget.source) {
                        LobbySource(:final seek) => LobbySeekCard(seek, found: true),
                        UserChallengeSource(:final challengeRequest) => UserChallengeCard(
                          challengeRequest,
                          found: true,
                        ),
                        ExistingGameSource() => null,
                      }
                    : null,
                clearing: pending.clearing,
                // After a game, its player tables were already in place.
                tablesEnter: pending.fromSearch,
                onStarted: _consumeIntro,
              )
            : null;

        final socketUri = GameController.socketUri(gameId);

        final body = PopScope(
          canPop: isRealTimePlayingGame != true,
          child: SafeArea(
            // view padding can change on Android when immersive mode is enabled, so to prevent any
            // board vertical shift, we set `maintainBottomViewPadding` to true.
            maintainBottomViewPadding: true,
            child: GameBody(
              // A new game gets a new board, rather than updating the previous game's.
              key: ValueKey(gameId),
              gameId: gameId,
              // Only show the initial loading position if this is still the game that the GameScreen
              // was created for. This will not be the case when searching for a new opponent after the game.
              loadingPosition: switch (widget.source) {
                ExistingGameSource(:final id) when id == gameId => widget.loadingPosition,
                _ => null,
              },
              whiteClockKey: _whiteClockKey,
              blackClockKey: _blackClockKey,
              boardKey: _boardKey,
              intro: gameId == createdGameId ? intro : null,
              onLoadGameCallback: (id) {
                if (mounted) {
                  ref.read(gameScreenLoaderProvider(widget.source).notifier).loadGame(id);
                }
              },
              onNewOpponentCallback: (game) {
                if (!mounted) return;

                if (widget.source is LobbySource) {
                  ref.read(gameScreenLoaderProvider(widget.source).notifier).newOpponent();
                } else {
                  final savedSetup = ref.read(gameSetupPreferencesProvider);
                  Navigator.of(context).pushReplacementHidingTabBar(
                    GameScreen.buildRoute(
                      source: LobbySource(GameSeek.newOpponentFromGame(game, savedSetup)),
                    ),
                  );
                }
              },
            ),
          ),
        );

        return PlatformScaffold(
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          appBar: PlatformAppBar(
            leading: isRealTimePlayingGame
                ? AppBarIndicator(child: SocketPingRatingIcon(socketUri: socketUri))
                : null,
            title: _GameTitle(
              _StandaloneTitleVariant(id: gameId, lastMoveAt: widget.lastMoveAt),
              monitorSocket: isRealTimePlayingGame,
              socketUri: socketUri,
            ),
            // The menu is rebuilt with the game state fields it shows, not the whole screen: every
            // rebuild of the actions also redraws the pinned bar buttons on iOS 26.
            actionsBuilder: (context, ref) => [
              if (ref.watch(
                    gameControllerProvider(gameId).select(
                      (s) => s.value == null
                          ? null
                          : (
                              nbWatchers: s.value!.nbWatchers,
                              bookmarked: s.value!.game.bookmarked == true,
                              youAre: s.value!.game.youAre,
                              finished: s.value!.game.finished,
                            ),
                    ),
                  )
                  case final menuState?)
                ContextMenuIconButton(
                  icon: const Icon(Icons.more_horiz),
                  semanticsLabel: context.l10n.menu,
                  actions: [
                    if (menuState.nbWatchers > 0)
                      ContextMenuAction(
                        icon: Icons.person_outline,
                        label: 'Spectators (${menuState.nbWatchers})',
                        onPressed: () {
                          final s = ref.read(gameControllerProvider(gameId)).value;
                          if (s == null) return;
                          showAdaptiveDraggableBottomSheet<void>(
                            context: context,
                            builder: (_, scrollController) => WatcherListBottomSheet(
                              nbWatchers: s.nbWatchers,
                              watcherNames: s.watcherNames,
                              scrollController: scrollController,
                            ),
                          );
                        },
                      ),
                    ContextMenuAction(
                      icon: menuState.bookmarked
                          ? Icons.bookmark_remove_outlined
                          : Icons.bookmark_add_outlined,
                      label: menuState.bookmarked
                          ? context.l10n.mobileRemoveBookmark
                          : context.l10n.bookmarkThisGame,
                      onPressed: () =>
                          ref.read(gameControllerProvider(gameId).notifier).toggleBookmark(),
                    ),
                    ContextMenuAction(
                      icon: Theme.of(context).platform == TargetPlatform.iOS
                          ? Icons.ios_share_outlined
                          : Icons.share_outlined,
                      label: context.l10n.mobileShare,
                      onPressed: null,
                      submenu: makeFinishedGameShareMenuActions(
                        context,
                        ref,
                        gameId: gameId.gameId,
                        orientation: menuState.youAre ?? Side.white,
                        finished: menuState.finished,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: Theme.of(context).platform == TargetPlatform.android
              ? AndroidImmersiveModeWidget(
                  enabled:
                      isRealTimePlayingGame &&
                      (boardPreferences.immersiveModeWhilePlaying ?? false),
                  child: body,
                )
              : body,
        );
      case AsyncData(value: OpenChallengeCreatedState(:final challenge)):
        return PlatformScaffold(
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          appBar: PlatformAppBar(
            leading: const AppBarIndicator(child: SocketPingRatingIcon()),
            title: _GameTitle(
              _ChallengeTitleVariant((widget.source as UserChallengeSource).challengeRequest),
              monitorSocket: true,
            ),
          ),
          body: PopScope(
            canPop: false,
            child: OpenChallengeLoadingContent(
              id: challenge.id,
              challengeRequest: (widget.source as UserChallengeSource).challengeRequest,
              cancelChallenge: ref.read(createGameServiceProvider).cancelChallenge,
            ),
          ),
        );
      case AsyncError(error: final e, stackTrace: final s):
        debugPrint('SEVERE: [GameScreen] could not create game; $e\n$s');

        // lichess sends a 400 response if user has not allowed challenges
        final message = e is ServerException && e.statusCode == 400
            ? LoadGameError('Could not create the game: ${e.jsonError?['error']}')
            : const LoadGameError('Sorry, we could not create the game. Please try again later.');

        return PlatformScaffold(
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          appBar: PlatformAppBar(
            leading: const AppBarIndicator(child: SocketPingRatingIcon()),
            title: switch (widget.source) {
              LobbySource(:final seek) => _GameTitle(_LobbyTitleVariant(seek), monitorSocket: true),
              UserChallengeSource(:final challengeRequest) => _GameTitle(
                _ChallengeTitleVariant(challengeRequest),
                monitorSocket: true,
              ),
              _ => null,
            },
          ),
          body: PopScope(child: message),
        );
      case _:
        final loadingBoard = switch (widget.source) {
          LobbySource(:final seek) => LobbyScreenLoadingContent(
            seek,
            () => ref.read(createGameServiceProvider).cancelSeek(),
            clearing: _searchClearing,
          ),
          UserChallengeSource(:final challengeRequest) => UserChallengeLoadingContent(
            challengeRequest,
            () => ref.read(createGameServiceProvider).cancelChallenge(),
          ),
          ExistingGameSource() => StandaloneGameLoadingContent(
            loadingParam: widget.loadingPosition,
            userActionsBar: const BottomBar.empty(cupertinoGlass: true),
          ),
        };

        return PlatformScaffold(
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          appBar: PlatformAppBar(
            leading: const AppBarIndicator(child: SocketPingRatingIcon()),
            title: switch (widget.source) {
              LobbySource(:final seek) => _GameTitle(_LobbyTitleVariant(seek), monitorSocket: true),
              UserChallengeSource(:final challengeRequest) when challengeRequest.destUser != null =>
                _GameTitle(_ChallengeTitleVariant(challengeRequest), monitorSocket: true),
              _ => null,
            },
          ),
          body: PopScope(canPop: false, child: WakelockWidget(child: loadingBoard)),
        );
    }
  }
}

sealed class const _GameTitleVariant();

final _isRealTimePlayableGameProvider = FutureProvider.autoDispose.family<bool, GameFullId>((
  Ref ref,
  GameFullId gameId,
) async {
  final state = await ref.watch(gameControllerProvider(gameId).future);
  return state.game.meta.speed != Speed.correspondence && state.game.playable;
}, name: 'IsRealTimePlayableGameProvider');

/// A game whose match intro waits for it to load. See [_GameScreenState._pendingIntro].
typedef _PendingIntro = ({
  GameFullId gameId,

  /// Found by a search, rather than loaded from the game on screen.
  bool fromSearch,

  /// The finished game's board, to clear off before the new game drops in.
  MatchIntroBoard? clearing,
});

final class const _LobbyTitleVariant(final GameSeek seek) extends _GameTitleVariant;

final class const _ChallengeTitleVariant(final ChallengeRequest challenge)
    extends _GameTitleVariant;

final class const _StandaloneTitleVariant({
  required final GameFullId id,
  final DateTime? lastMoveAt,
}) extends _GameTitleVariant;

/// Single title widget for all GameScreen AppBar configurations.
///
/// When [monitorSocket] is true, shows "Reconnecting" if the socket is
/// disconnected (ping rating == 0). [socketUri] scopes the ping check to a
/// specific socket; null monitors the currently active route.
class const _GameTitle(
  final _GameTitleVariant variant, {
  final bool monitorSocket = false,
  final Uri? socketUri,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (monitorSocket && ref.watch(socketPingProvider(socketUri)).rating == 0) {
      return AppBarTitleText(context.l10n.reconnecting);
    }

    return switch (variant) {
      _LobbyTitleVariant(:final seek) => _buildLobbyContent(context, seek),
      _ChallengeTitleVariant(:final challenge) => _buildChallengeContent(context, challenge),
      _StandaloneTitleVariant(:final id, :final lastMoveAt) => _ExportedGameTitle(
        id: id,
        lastMoveAt: lastMoveAt,
      ),
    };
  }

  static Widget _buildLobbyContent(BuildContext context, GameSeek seek) {
    final mode = seek.rated ? ' • ${context.l10n.rated}' : ' • ${context.l10n.casual}';
    return _SearchTitleRow(icon: seek.perf.icon, text: '${seek.timeIncrement?.display}$mode');
  }

  static Widget _buildChallengeContent(BuildContext context, ChallengeRequest challenge) {
    final mode = challenge.rated ? ' • ${context.l10n.rated}' : ' • ${context.l10n.casual}';
    return _SearchTitleRow(
      icon: challenge.perf.icon,
      text: challenge.timeIncrement != null
          ? '${challenge.timeIncrement?.display}$mode'
          : challenge.days != null
          ? '${context.l10n.nbDays(challenge.days!)}$mode'
          : null,
    );
  }
}

/// Title of a search screen, laid out like [ExportedGameTitle] (the title of the game it turns
/// into), so that the title stays put when the game starts.
class const _SearchTitleRow({required final IconData icon, final String? text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      children: [
        Icon(icon, color: DefaultTextStyle.of(context).style.color),
        const SizedBox(width: 8.0),
        if (text != null)
          Flexible(
            child: AppBarTitleText(text!, maxLines: 1, minFontSize: 13.0, maxFontSize: 16.0),
          ),
      ],
    );
  }
}

final _gameMetaProvider = FutureProvider.autoDispose.family<GameMeta, GameFullId>((
  Ref ref,
  GameFullId gameId,
) async {
  // Using ref.read as an optimization since we know that game meta never changes during the game.
  return (await ref.read(gameControllerProvider(gameId).future)).game.meta;
}, name: 'GameMetaProvider');

class const _ExportedGameTitle({required final GameFullId id, final DateTime? lastMoveAt})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While the provider resolves (a frame), use the meta of a game that is already loaded, so the
    // title doesn't flash its loading placeholder when a found game takes over the search screen.
    final metaAsync = ref.watch(_gameMetaProvider(id));
    final meta = metaAsync.value ?? ref.read(gameControllerProvider(id)).value?.game.meta;
    return switch (metaAsync) {
      _ when meta != null => ExportedGameTitle(meta: meta, lastMoveAt: lastMoveAt),
      AsyncError() => const SizedBox.shrink(),
      _ => const ExportedGameTitleLoading(),
    };
  }
}
