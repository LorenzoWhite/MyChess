import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/board_assets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('BoardAssetCatalog.fromJson', () {
    test('parses piece sets and board themes', () {
      final catalog = BoardAssetCatalog.fromJson(const {
        'version': 1,
        'pieceSets': [
          {
            'id': 'neon',
            'label': 'Neon',
            'dir': 'assets/custom/piece_sets/neon/',
            'extension': '.png',
          },
        ],
        'boardThemes': [
          {
            'id': 'my-wood',
            'label': 'My Wood',
            'lightSquare': 'f0d9b6',
            'darkSquare': '#b58863',
            'texture': 'assets/custom/boards/my-wood.png',
            'thumbnail': 'assets/custom/boards/my-wood-thumb.jpg',
          },
        ],
      });

      expect(catalog.pieceSets, hasLength(1));
      final pieceSet = catalog.pieceSets.first;
      expect(pieceSet.id, 'neon');
      expect(pieceSet.label, 'Neon');
      expect(pieceSet.assets, hasLength(PieceKind.values.length));
      expect(
        pieceSet.assets[PieceKind.whiteKing],
        const AssetImage('assets/custom/piece_sets/neon/wK.png'),
      );
      expect(
        pieceSet.assets[PieceKind.blackPawn],
        const AssetImage('assets/custom/piece_sets/neon/bP.png'),
      );

      expect(catalog.boardThemes, hasLength(1));
      final theme = catalog.boardThemes.first;
      expect(theme.id, 'my-wood');
      expect(theme.colors.lightSquare, const Color(0xfff0d9b6));
      expect(theme.colors.darkSquare, const Color(0xffb58863));
      expect(theme.colors.background, isA<ImageChessboardBackground>());
      expect(theme.colors.whiteCoordBackground, isA<ImageChessboardBackground>());
      expect(theme.thumbnail, const AssetImage('assets/custom/boards/my-wood-thumb.jpg'));
    });

    test('parses a flat theme without a texture', () {
      final catalog = BoardAssetCatalog.fromJson(const {
        'boardThemes': [
          {'id': 'flat', 'label': 'Flat', 'lightSquare': 'ffffff', 'darkSquare': '000000'},
        ],
      });

      final theme = catalog.boardThemes.first;
      expect(theme.colors.background, isA<SolidColorChessboardBackground>());
      expect(theme.thumbnail, isNull);
      expect(theme.colors.lastMove.solidColor, const Color(0x809cc700));
    });

    test('skips invalid entries but keeps valid ones', () {
      final catalog = BoardAssetCatalog.fromJson(const {
        'pieceSets': [
          {'id': 'Bad Id', 'label': 'Bad', 'dir': 'assets/x'},
          {'label': 'No id', 'dir': 'assets/x'},
          {'id': 'ok', 'label': 'Ok', 'dir': 'assets/y'},
        ],
        'boardThemes': [
          {'id': 'bad-colour', 'label': 'Bad', 'lightSquare': 'nope', 'darkSquare': '000000'},
          {'id': 'ok-theme', 'label': 'Ok', 'lightSquare': 'ffffff', 'darkSquare': '000000'},
        ],
      });

      expect(catalog.pieceSets.map((s) => s.id), ['ok']);
      expect(catalog.boardThemes.map((t) => t.id), ['ok-theme']);
    });

    test('ignores duplicate ids', () {
      final catalog = BoardAssetCatalog.fromJson(const {
        'pieceSets': [
          {'id': 'dup', 'label': 'First', 'dir': 'assets/a'},
          {'id': 'dup', 'label': 'Second', 'dir': 'assets/b'},
        ],
      });

      expect(catalog.pieceSets, hasLength(1));
      expect(catalog.pieceSets.first.label, 'First');
    });

    test('tolerates an empty manifest', () {
      final catalog = BoardAssetCatalog.fromJson(const {});
      expect(catalog.isEmpty, isTrue);
    });

    test('falls back to cburnett for an unknown shareAs', () {
      final catalog = BoardAssetCatalog.fromJson(const {
        'pieceSets': [
          {'id': 'neon', 'label': 'Neon', 'dir': 'assets/x', 'shareAs': 'not-a-set'},
        ],
      });

      expect(catalog.pieceSets.first.shareAs, CustomPieceSet.defaultShareAs);
    });

    test('throws on a malformed document', () {
      expect(() => BoardAssetCatalog.fromJson(const {'pieceSets': 'nope'}), throwsFormatException);
    });
  });

  group('PieceSetChoice', () {
    test('round trips built-in storage keys', () {
      final choice = PieceSetChoice.fromStorageKey('merida');
      expect(choice, const BuiltinPieceSetChoice(PieceSet.merida));
      expect(choice.storageKey, 'merida');
      expect(choice.shareName, 'merida');
    });

    test('falls back for unknown keys', () {
      expect(PieceSetChoice.fromStorageKey('custom:missing'), PieceSetChoice.fallback);
      expect(PieceSetChoice.fromStorageKey('nonsense'), PieceSetChoice.fallback);
    });

    test('resolves custom ids from the loaded catalog', () {
      final catalog = BoardAssetCatalog.fromJson(const {
        'pieceSets': [
          {
            'id': 'neon',
            'label': 'Neon',
            'dir': 'assets/custom/piece_sets/neon',
            'shareAs': 'staunty',
          },
        ],
      });
      BoardAssetCatalogNotifier.current = catalog;
      addTearDown(() => BoardAssetCatalogNotifier.current = BoardAssetCatalog.empty);

      final choice = PieceSetChoice.fromStorageKey('custom:neon');
      expect(choice, isA<CustomPieceSetChoice>());
      expect(choice.label, 'Neon');
      expect(choice.storageKey, 'custom:neon');
      expect(choice.shareName, 'staunty');
    });

    test('converter stores and reads storage keys', () {
      const converter = PieceSetChoiceConverter();
      const choice = BuiltinPieceSetChoice(PieceSet.cburnett);
      expect(converter.toJson(choice), 'cburnett');
      expect(converter.fromJson('cburnett'), choice);
    });
  });
}
