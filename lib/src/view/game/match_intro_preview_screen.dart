import 'dart:convert';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/game/game_board_params.dart';
import 'package:lichess_mobile/src/model/game/playable_game.dart';
import 'package:lichess_mobile/src/model/lobby/game_seek.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/game/game_loading_board.dart';
import 'package:lichess_mobile/src/view/game/game_player.dart';
import 'package:lichess_mobile/src/view/game/match_intro.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/game_layout.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

/// How long the preview shows the found card before the intro starts, as if the game were loading.
const _kLoadingHold = Duration(milliseconds: 500);

/// Developer screen to tune the match intro and the player bars without having to find a real game.
///
/// Replays the hand-over from the search card to the game board, with real player bars for a sample
/// game. Not shown in release builds (see the settings screen).
class const MatchIntroPreviewScreen() extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const MatchIntroPreviewScreen());
  }

  @override
  ConsumerState<MatchIntroPreviewScreen> createState() => _MatchIntroPreviewScreenState();
}

class _MatchIntroPreviewScreenState()
    extends ConsumerState<MatchIntroPreviewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  Side _side = Side.white;
  bool _slowMotion = false;
  bool _landed = false;

  /// Plays the intro of a rematch: a finished game is cleared off the board first.
  bool _rematch = false;

  /// Shows registered players (title, rating, flair) in the bars instead of anonymous ones.
  bool _registered = false;

  /// Plays a few moves with captures, to show the material on the bars' second line.
  bool _captures = false;

  static const _seek = GameSeek(clock: (Duration(minutes: 5), Duration.zero), rated: false);

  /// The finished game a rematch starts from. Colours swap in a rematch, so it was played from the
  /// other side.
  static const _finishedGameFen = 'r1bq1rk1/pp3ppp/2n2n2/3p4/3P4/2NB1N2/PP3PPP/R2Q1RK1 w - - 0 11';

  MatchIntroTimeline get _timeline => MatchIntroTimeline(clearsBoard: _rematch);

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: _timeline.duration)..addListener(_onTick);
    _replay();
  }

  @override
  void dispose() {
    timeDilation = 1.0;
    _intro.dispose();
    super.dispose();
  }

  void _onTick() {
    final landed = _intro.value >= _timeline.piecesLanded;
    if (landed != _landed) setState(() => _landed = landed);
  }

  Future<void> _replay() async {
    _intro.duration = _timeline.duration;
    _intro.value = 0.0;
    await Future<void>.delayed(_kLoadingHold * timeDilation);
    if (mounted) _intro.forward();
  }

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final bottomSide = _side;
    final game = _previewGame(
      registered: _registered,
      youAre: bottomSide,
      pgn: _captures ? _kCapturesPgn : '',
    );

    return PlatformScaffold(
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: false,
      appBar: PlatformAppBar(
        title: const Text('Match intro'),
        actions: [
          IconButton(
            tooltip: 'Play as ${_side.opposite.name}',
            icon: const Icon(Icons.swap_vert),
            onPressed: () {
              setState(() => _side = _side.opposite);
              _replay();
            },
          ),
          IconButton(
            tooltip: 'Registered players',
            isSelected: _registered,
            icon: const Icon(Icons.badge_outlined),
            onPressed: () => setState(() => _registered = !_registered),
          ),
          IconButton(
            tooltip: 'Captures',
            isSelected: _captures,
            icon: const Icon(Icons.content_cut),
            onPressed: () => setState(() => _captures = !_captures),
          ),
          IconButton(
            tooltip: 'Rematch',
            isSelected: _rematch,
            icon: const Icon(Icons.restart_alt),
            onPressed: () {
              setState(() => _rematch = !_rematch);
              _replay();
            },
          ),
          IconButton(
            tooltip: 'Slow motion',
            isSelected: _slowMotion,
            icon: const Icon(Icons.slow_motion_video),
            onPressed: () {
              setState(() => _slowMotion = !_slowMotion);
              timeDilation = _slowMotion ? 5.0 : 1.0;
            },
          ),
          IconButton(tooltip: 'Replay', icon: const Icon(Icons.replay), onPressed: _replay),
        ],
      ),
      body: SafeArea(
        child: GameLayout(
          orientation: bottomSide,
          boardParams: _landed
              ? GameBoardParams.readonly(variant: Variant.standard, position: game.lastPosition)
              : GameBoardParams.emptyBoard,
          moves: const [],
          boardOverlay: _rematch
              ? null
              : MatchIntroCard(
                  animation: _intro,
                  timeline: _timeline,
                  card: const LobbySeekCard(_seek, found: true),
                ),
          boardForeground: MatchIntroPieces(
            animation: _intro,
            timeline: _timeline,
            pieces: readFen(game.lastPosition.fen),
            orientation: bottomSide,
            clearing: _rematch
                ? (pieces: readFen(_finishedGameFen), orientation: bottomSide.opposite)
                : null,
            pieceAssets: boardPrefs.pieceSet.assets,
          ),
          topTable: MatchIntroEntrance(
            animation: _rematch ? kAlwaysCompleteAnimation : _intro,
            interval: _timeline.topTable,
            from: const Offset(0.0, -0.35),
            child: _PreviewPlayer(game: game, side: bottomSide.opposite),
          ),
          bottomTable: MatchIntroEntrance(
            animation: _rematch ? kAlwaysCompleteAnimation : _intro,
            interval: _timeline.bottomTable,
            from: const Offset(0.0, 0.35),
            child: _PreviewPlayer(game: game, side: bottomSide, prominent: true),
          ),
          userActionsBar: BottomBar(
            cupertinoGlass: true,
            contentOpacity: _intro.drive(CurveTween(curve: _timeline.bottomBar)),
            children: [
              BottomBarButton(label: 'Menu', icon: Icons.menu, onTap: () {}),
              BottomBarButton(label: 'Chat', icon: Icons.chat_bubble_outline, onTap: () {}),
              BottomBarButton(label: 'Back', icon: Icons.chevron_left, onTap: () {}),
              BottomBarButton(label: 'Forward', icon: Icons.chevron_right, onTap: () {}),
            ],
          ),
        ),
      ),
    );
  }
}

/// Légal's trap without the mate: Black is up a queen for two pawns.
const _kCapturesPgn = 'e4 e5 Nf3 d6 Bc4 Bg4 Nc3 g6 Nxe5 Bxd1 Bxf7+ Ke7';

/// A sample game for the player bars, as the server would send it: anonymous players, or
/// registered ones with a title, a flair and ratings.
PlayableGame _previewGame({required bool registered, required Side youAre, required String pgn}) {
  String player(String name, {String? title, required int rating}) => registered
      ? '''
{
  "user": {
    "name": "$name",
    "id": "${name.toLowerCase()}",
    ${title != null ? '"title": "$title",' : ''}
    "flair": "activity.lichess"
  },
  "rating": $rating,
  "onGame": true
}'''
      : '{"onGame": true}';
  final json =
      '''
{
  "game": {
    "id": "preview1",
    "variant": {"key": "standard", "name": "Standard", "short": "Std"},
    "speed": "blitz",
    "perf": "blitz",
    "rated": false,
    "source": "lobby",
    "status": {"id": 20, "name": "started"},
    "createdAt": 1685698678928,
    "pgn": "$pgn"
  },
  "white": ${player('Magnus', title: 'GM', rating: 2850)},
  "black": ${player('Elvi', rating: 1790)},
  "clock": {
    "running": false,
    "initial": 300,
    "increment": 0,
    "white": 300.0,
    "black": 300.0,
    "emerg": 30,
    "moretime": 15
  },
  "youAre": "${youAre.name}",
  "socket": 0
}''';
  return PlayableGame.fromServerJson(jsonDecode(json) as Map<String, dynamic>);
}

/// A real player bar for the preview: the player's clock runs, the opponent's doesn't.
class const _PreviewPlayer({
  required final PlayableGame game,
  required final Side side,
  final bool prominent = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GamePlayer(
      game: game,
      side: side,
      prominent: prominent,
      mePlaying: side == game.youAre,
      shouldLinkToUserProfile: false,
      materialDiff: game.materialDiffAt(game.steps.length - 1, side),
      clock: PlayerBarClock(
        timeLeft: const Duration(minutes: 5),
        active: prominent,
        prominent: prominent,
      ),
    );
  }
}
