import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/challenge/challenge.dart';
import 'package:lichess_mobile/src/model/challenge/challenge_repository.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/model/common/time_increment.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/settings/brightness.dart';
import 'package:lichess_mobile/src/styles/icon_extensions.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/utils/share.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/view/game/game_body.dart';
import 'package:lichess_mobile/src/view/game/game_screen.dart';
import 'package:lichess_mobile/src/view/game/game_screen_providers.dart';
import 'package:lichess_mobile/src/view/game/match_intro.dart';
import 'package:lichess_mobile/src/view/user/pick_player_screen.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/shimmer.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Status line of the lobby's search card while it looks for an opponent.
const _kFindingOpponentText = 'Finding opponent';

/// Status line of the lobby's search card once it has found an opponent, while the game loads.
const _kOpponentFoundText = 'Opponent found';

/// Status line of a challenge's search card once the challenge is accepted, while the game loads.
const _kChallengeAcceptedText = 'Challenge accepted';

/// Width of the search cards' content. Fixed, so that a card keeps its size when its status changes.
const _kSearchCardContentWidth = 220.0;

class const LobbyScreenLoadingContent(
  final GameSeek seek,
  final Future<void> Function() cancelGameCreation, {

  /// True once the seek has been matched, while the game loads: the card says the opponent is found
  /// and there is nothing left to cancel. The screen then hands over to the game board, which draws
  /// the same card and plays the match intro (see `match_intro.dart`).
  final bool isStarting = false,

  /// The board of the game this search replaces ("new opponent"), whose pieces are lifted off as the
  /// search card comes in.
  final MatchIntroBoard? clearing,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GameLayout(
        orientation: Side.white,
        // Empty while searching: the side is not known yet, and an empty board looks the same from
        // both sides, so nothing has to flip when the game starts.
        boardParams: GameBoardParams.emptyBoard,
        moves: const [],
        boardOverlay: _SearchCardEntrance(child: LobbySeekCard(seek, found: isStarting)),
        boardForeground: clearing != null ? MatchIntroClearPieces(board: clearing!) : null,
        userActionsBar: BottomBar(
          cupertinoGlass: true,
          children: [
            _CancelSearchButton(
              cancel: cancelGameCreation,
              errorMessage: 'Error cancelling game creation',
              hidden: isStarting,
            ),
          ],
        ),
      ),
    );
  }
}

/// The card shown over the board while looking for an opponent in the lobby: the time control, a
/// spinner and a status line.
///
/// The game board draws it again, [found], at the start of the match intro: it must look the same in
/// both places for the hand-over to be seamless.
class const LobbySeekCard(final GameSeek seek, {final bool found = false}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // The rating range only when the player set one: the default (-500, +500) says nothing.
    final ratingRange = switch (seek.ratingRange) {
      (final min, final max) when min + 1000 != max => (min, max),
      _ => null,
    };
    return _SearchCard(
      header: [
        _GameParamsDisplay.seek(seek),
        if (ratingRange != null) ...[
          const SizedBox(height: 4.0),
          RatingPrefAware(
            child: Text(
              '${ratingRange.$1}–${ratingRange.$2}',
              style: TextTheme.of(context).bodyMedium,
            ),
          ),
        ],
      ],
      status: found ? _kOpponentFoundText : _kFindingOpponentText,
      found: found,
    );
  }
}

class const UserChallengeLoadingContent(
  final ChallengeRequest challenge,
  final Future<void> Function() cancelChallenge, {

  /// True once the challenge has been accepted, while the game loads. See
  /// [LobbyScreenLoadingContent.isStarting].
  final bool isStarting = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GameLayout(
        orientation: Side.white,
        boardParams: GameBoardParams.emptyBoard,
        moves: const [],
        boardOverlay: _SearchCardEntrance(child: UserChallengeCard(challenge, found: isStarting)),
        userActionsBar: BottomBar(
          cupertinoGlass: true,
          children: [
            _CancelSearchButton(
              cancel: cancelChallenge,
              errorMessage: 'Error cancelling challenge',
              hidden: isStarting,
            ),
          ],
        ),
      ),
    );
  }
}

/// The card shown over the board while waiting for a challenged player to accept: who, the time
/// control, a spinner and a status line.
///
/// Drawn again by the game board at the start of the match intro, like [LobbySeekCard].
class const UserChallengeCard(final ChallengeRequest challenge, {final bool found = false})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SearchCard(
      header: [
        UserFullNameWidget(user: challenge.destUser, style: TextTheme.of(context).titleLarge),
        const SizedBox(height: 6.0),
        _GameParamsDisplay.challengeRequest(challenge),
      ],
      status: found ? _kChallengeAcceptedText : context.l10n.waitingForOpponent,
      found: found,
    );
  }
}

/// Layout shared by the search cards: what is searched for ([header]), then a spinner that turns
/// into a check mark once [found], and a [status] line.
///
/// Its width is fixed and its lines are the same in both states, so the card never changes size.
class const _SearchCard({
  required final List<Widget> header,
  required final String status,
  required final bool found,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textColor = DefaultTextStyle.of(context).style.color;
    return _BoardOverlayCard(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
      child: SizedBox(
        width: _kSearchCardContentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...header,
            const SizedBox(height: 22.0),
            SizedBox.square(
              dimension: 32.0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: found
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('found'),
                        size: 32.0,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : CircularProgressIndicator(
                        key: const ValueKey('searching'),
                        strokeWidth: 2.5,
                        color: textColor,
                      ),
              ),
            ),
            const SizedBox(height: 12.0),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                status,
                key: ValueKey(status),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextTheme.of(context).bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and scales the search card in.
class const _SearchCardEntrance({required final Widget child}) extends StatefulWidget {
  @override
  State<_SearchCardEntrance> createState() => _SearchCardEntranceState();
}

class _SearchCardEntranceState()
    extends State<_SearchCardEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect reduce-motion: show the card at rest instead of animating it.
    if (MediaQuery.disableAnimationsOf(context)) _entrance.value = 1.0;
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _entrance,
      child: ScaleTransition(
        scale: _entrance.drive(
          Tween(begin: 0.94, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)),
        ),
        child: widget.child,
      ),
    );
  }
}

/// The Cancel button of a search screen.
///
/// Once the opponent is found ([hidden]) it fades out but the bar stays, so the bar does not flash
/// when the game's buttons fade in over it.
class const _CancelSearchButton({
  required final Future<void> Function() cancel,
  required final String errorMessage,
  final bool hidden = false,
}) extends StatefulWidget {
  @override
  State<_CancelSearchButton> createState() => _CancelSearchButtonState();
}

class _CancelSearchButtonState() extends State<_CancelSearchButton> {
  Future<void>? _cancelFuture;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: widget.hidden,
      child: AnimatedOpacity(
        opacity: widget.hidden ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: FutureBuilder(
          future: _cancelFuture,
          builder: (context, snapshot) {
            return BottomBarButton(
              onTap: snapshot.connectionState == ConnectionState.waiting
                  ? null
                  : () async {
                      setState(() {
                        _cancelFuture = widget.cancel();
                      });
                      try {
                        await _cancelFuture;
                      } catch (_) {
                        if (context.mounted) {
                          showSnackBar(context, widget.errorMessage, type: SnackBarType.error);
                        }
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              label: context.l10n.cancel,
              showLabel: true,
              icon: CupertinoIcons.xmark,
            );
          },
        ),
      ),
    );
  }
}

class const OpenChallengeLoadingContent({
  required final ChallengeId id,
  required final ChallengeRequest challengeRequest,
  required final Future<void> Function() cancelChallenge,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<OpenChallengeLoadingContent> createState() => _OpenChallengeLoadingContentState();
}

class _OpenChallengeLoadingContentState() extends ConsumerState<OpenChallengeLoadingContent> {
  Future<void>? _cancelChallengeFuture;

  @override
  Widget build(BuildContext context) {
    final challengeLink = 'https://$kLichessHost/game/${widget.id}';
    final authUser = ref.watch(authControllerProvider);

    final qrColor = ref.watch(currentBrightnessProvider) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Column(
      children: [
        Expanded(
          child: SafeArea(
            child: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.emptyBoard,
              moves: const [],
              boardOverlay: _BoardOverlayCard(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 20.0,
                  children: [
                    _GameParamsDisplay.challengeRequest(widget.challengeRequest),
                    Text(context.l10n.toInviteSomeoneToPlayGiveThisUrl),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: GestureDetector(
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: challengeLink));
                          if (!context.mounted) return;
                          showSnackBar(context, context.l10n.mobileCopied);
                        },
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Icon(Icons.copy),
                              ),
                              TextSpan(text: ' $challengeLink'),
                            ],
                          ),
                          style: TextTheme.of(context).bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),

                    Text(context.l10n.theFirstPersonToComeOnThisUrlWillPlayWithYou),

                    if (authUser != null)
                      FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          PickPlayerScreen.buildRoute(
                            title: Text(context.l10n.challengeAFriend),
                            onUserTap: (user) async {
                              // Capture everything that needs BuildContext before the async gap.
                              final navigator = Navigator.of(context);
                              final directedChallengeReq = widget.challengeRequest.copyWith(
                                destUser: user,
                              );
                              final directedChallengeRoute =
                                  widget.challengeRequest.timeControl ==
                                      ChallengeTimeControlType.clock
                                  ? GameScreen.buildRoute(
                                      source: UserChallengeSource(directedChallengeReq),
                                    )
                                  : null;

                              try {
                                await widget.cancelChallenge();
                              } catch (e) {
                                debugPrint('Error cancelling open challenge: $e');
                              }

                              if (!context.mounted) return;

                              if (directedChallengeRoute != null) {
                                // Invalidate the provider so the new GameScreen creates a
                                // fresh challenge even if the same UserChallengeSource was
                                // used in a previous game (Freezed equality shares providers).
                                ref.invalidate(
                                  gameScreenLoaderProvider(
                                    UserChallengeSource(directedChallengeReq),
                                  ),
                                );
                                // Use pushAndRemoveUntil to clear any old GameScreen from
                                // the stack without removing unrelated routes.
                                navigator.pushAndRemoveUntilHidingTabBar(
                                  directedChallengeRoute,
                                  (route) => route is! ScreenRoute || route.screen is! GameScreen,
                                );
                              } else {
                                await ref
                                    .read(challengeRepositoryProvider)
                                    .create(directedChallengeReq);
                                if (!context.mounted) return;
                                showSnackBar(
                                  context,
                                  context.l10n.mobileChallengeCreated.replaceAll('\\n', '\n'),
                                );
                                // Back to the screen below the game
                                Navigator.of(context).popUntilTabBarShown();
                              }
                            },
                          ),
                        ),
                        label: Text(context.l10n.challengeInviteLichessUser.replaceAll(':', '')),
                        icon: const Icon(Icons.person_search),
                      ),

                    Container(
                      padding: const EdgeInsets.all(4.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: QrImageView(
                        data: challengeLink,
                        eyeStyle: QrEyeStyle(color: qrColor, eyeShape: QrEyeShape.square),
                        dataModuleStyle: QrDataModuleStyle(
                          color: qrColor,
                          dataModuleShape: QrDataModuleShape.square,
                        ),
                        version: QrVersions.auto,
                        size: 120.0,
                        padding: const EdgeInsets.all(12.0),
                      ),
                    ),

                    Text(context.l10n.orLetYourOpponentScanQrCode),
                  ],
                ),
              ),
            ),
          ),
        ),
        BottomBar(
          cupertinoGlass: true,
          children: [
            Builder(
              builder: (context) => BottomBarButton(
                label: context.l10n.mobileShareChallengeUrl,
                onTap: () => launchShareDialog(context, ShareParams(text: challengeLink)),
                showLabel: true,
                icon: Icons.share,
              ),
            ),
            FutureBuilder(
              future: _cancelChallengeFuture,
              builder: (context, snapshot) {
                return BottomBarButton(
                  onTap: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () async {
                          setState(() {
                            _cancelChallengeFuture = widget.cancelChallenge();
                          });
                          try {
                            await _cancelChallengeFuture;
                          } catch (_) {
                            if (context.mounted) {
                              showSnackBar(
                                context,
                                'Error cancelling challenge',
                                type: SnackBarType.error,
                              );
                            }
                          }
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  label: context.l10n.cancel,
                  showLabel: true,
                  icon: CupertinoIcons.xmark,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _GameParamsDisplay extends StatelessWidget {
  const new({required this.perf, required this.timeIncrement, required this.days});

  new seek(GameSeek seek) : perf = seek.perf, timeIncrement = seek.timeIncrement, days = seek.days;

  new challengeRequest(ChallengeRequest challenge)
    : perf = challenge.perf,
      timeIncrement = challenge.timeIncrement,
      days = challenge.days;

  final Perf perf;
  final TimeIncrement? timeIncrement;
  final int? days;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(perf.icon, color: DefaultTextStyle.of(context).style.color),
        const SizedBox(width: 8.0),
        Text(
          timeIncrement?.display ??
              (days != null ? '${context.l10n.daysPerTurn}: $days' : context.l10n.unlimited),
          style: TextTheme.of(context).titleLarge,
        ),
      ],
    );
  }
}

class const StandaloneGameLoadingContent({
  final LoadingParam? loadingParam,
  final Widget? userActionsBar,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final loadingFen = loadingParam?.fen;
    final variant = loadingParam?.variant ?? Variant.standard;
    Position? loadingPosition;
    if (loadingFen != null) {
      try {
        loadingPosition = Position.setupPosition(
          variant.rule,
          Setup.parseFen(loadingFen),
          ignoreImpossibleCheck: true,
        );
      } catch (_) {
        loadingPosition = null;
      }
    }
    final lastMove = loadingParam?.lastMove;
    return Shimmer(
      child: SafeArea(
        child: GameLayout(
          orientation: loadingParam?.orientation ?? Side.white,
          boardParams: loadingPosition == null
              ? GameBoardParams.emptyBoard
              : GameBoardParams.readonly(
                  variant: variant,
                  position: loadingPosition,
                  lastMove: switch (lastMove) {
                    // In crazyhouse games, the "ongoing games" endpoint does not return the correct UCI for crazyhouse games,
                    // e.g. instead of P@c4 the UCI will be c4c4.
                    // This leads to a "duplicate key" error, since chessground would try to highlight the same square twice.
                    // The dropped role does not matter, since we just use it for the square highlight.
                    NormalMove(:final from, :final to) when from == to => DropMove(
                      to: to,
                      role: Role.pawn,
                    ),
                    _ => lastMove,
                  },
                ),
          topTable: const LoadingPlayerWidget(),
          bottomTable: const LoadingPlayerWidget(),
          moves: const [],
          userActionsBar: userActionsBar,
        ),
      ),
    );
  }
}

/// A widget that shows a loading indicator for a player.
///
/// Must be wrapped in a [Shimmer] widget.
class const LoadingPlayerWidget({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      isLoading: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            flex: 6,
            child: SizedBox(
              height: 24.0,
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
            ),
          ),
          const Spacer(),
          Flexible(
            flex: 2,
            child: SizedBox(
              height: 38.0,
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(5.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const LoadGameError(final String errorMessage, {final bool showBottomBar = true})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SafeArea(
            child: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.emptyBoard,
              moves: const [],
              errorMessage: errorMessage,
            ),
          ),
        ),
        BottomBar(
          cupertinoGlass: true,
          children: [
            if (showBottomBar)
              BottomBarButton(
                onTap: () => Navigator.of(context).pop(),
                label: context.l10n.cancel,
                icon: CupertinoIcons.xmark,
                showLabel: true,
              ),
          ],
        ),
      ],
    );
  }
}

/// A board that shows a message that a challenge has been declined.
class const ChallengeDeclinedBoard({
  required final String declineReason,
  required final Challenge challenge,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textColor = DefaultTextStyle.of(context).style.color;

    return Column(
      children: [
        Expanded(
          child: SafeArea(
            child: GameLayout(
              orientation: Side.white,
              boardParams: GameBoardParams.emptyBoard,
              moves: const [],
              boardOverlay: _BoardOverlayCard(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.challengeChallengeDeclined,
                      style: TextTheme.of(context).titleMedium,
                    ),
                    const SizedBox(height: 8.0),
                    Divider(height: 26.0, thickness: 0.0, color: textColor),
                    Text(declineReason, style: const TextStyle(fontStyle: FontStyle.italic)),
                    Divider(height: 26.0, thickness: 0.0, color: textColor),
                    if (challenge.destUser != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(' — '),
                            Flexible(
                              fit: FlexFit.loose,
                              child: UserFullNameWidget(user: challenge.destUser?.user),
                            ),
                            if (challenge.destUser?.lagRating != null) ...[
                              const SizedBox(width: 6.0),
                              LagIndicator(lagRating: challenge.destUser!.lagRating!, size: 13.0),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        BottomBar(
          cupertinoGlass: true,
          children: [
            BottomBarButton(
              onTap: () => Navigator.of(context).pop(),
              label: context.l10n.cancel,
              icon: CupertinoIcons.xmark,
              showLabel: true,
            ),
          ],
        ),
      ],
    );
  }
}

class const _BoardOverlayCard({final EdgeInsetsGeometry? padding, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).dialogTheme.backgroundColor,
      elevation: 2.0,
      child: Padding(padding: padding ?? const EdgeInsets.all(30.0), child: child),
    );
  }
}
