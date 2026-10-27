import 'dart:convert';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

/// Location of the custom board assets manifest, relative to the app bundle.
const kBoardAssetsManifestPath = 'assets/custom/manifest.json';

/// The manifest schema version understood by this app.
///
/// A manifest with a higher version is still parsed on a best effort basis: unknown keys are
/// ignored and entries that fail to parse are skipped.
const kBoardAssetsManifestVersion = 1;

/// Prefix used to store a custom asset in preferences, e.g. `custom:neon`.
const _customIdPrefix = 'custom:';

/// Ids are used in preferences, so keep them simple and stable.
final _idRegExp = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

const _allowedExtensions = {'webp', 'png', 'jpg', 'jpeg'};

final _logger = Logger('BoardAssets');

/// The file name stem of [kind] inside a custom piece set directory, e.g. `wK` or `bP`.
///
/// This mirrors the naming used by lichess, so piece sets can be copied from the website as is.
String pieceAssetFileName(PieceKind kind) => switch (kind) {
  PieceKind.whiteKing => 'wK',
  PieceKind.whiteQueen => 'wQ',
  PieceKind.whiteRook => 'wR',
  PieceKind.whiteBishop => 'wB',
  PieceKind.whiteKnight => 'wN',
  PieceKind.whitePawn => 'wP',
  PieceKind.blackKing => 'bK',
  PieceKind.blackQueen => 'bQ',
  PieceKind.blackRook => 'bR',
  PieceKind.blackBishop => 'bB',
  PieceKind.blackKnight => 'bN',
  PieceKind.blackPawn => 'bP',
};

/// A piece set bundled in the app and declared in [kBoardAssetsManifestPath].
@immutable
class const CustomPieceSet({
  /// Stable identifier, stored in preferences as `custom:<id>`.
  required final String id,

  /// Human readable name shown in the settings screen.
  required final String label,

  /// The complete set of piece images.
  required final PieceAssets assets,

  /// A built-in lichess piece set name, sent to the lichess CDN when a game is exported as a
  /// GIF. The CDN does not know about custom sets, so custom art cannot appear there.
  final String shareAs = defaultShareAs,
}) {
  /// The built-in piece set used for GIF export when a custom set has no usable `shareAs`.
  static const defaultShareAs = 'cburnett';

  @override
  bool operator ==(Object other) => other is CustomPieceSet && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CustomPieceSet($id)';
}

/// A board theme bundled in the app and declared in [kBoardAssetsManifestPath].
@immutable
class const CustomBoardTheme({
  /// Stable identifier, stored in preferences as `custom:<id>`.
  required final String id,

  /// Human readable name shown in the settings screen.
  required final String label,

  /// The colour scheme, including the optional square texture.
  required final ChessboardColorScheme colors,

  /// Optional thumbnail shown in the board picker. Falls back to a colour swatch.
  final AssetImage? thumbnail,

  /// A built-in lichess board theme name used when exporting a game as a GIF.
  final String shareAs = defaultShareAs,
}) {
  /// The built-in board theme used for GIF export when a custom theme has no usable `shareAs`.
  static const defaultShareAs = 'brown';

  /// A thumbnail suitable for the board picker.
  Widget get thumbnailWidget => switch (thumbnail) {
    final AssetImage image => Image(image: image, height: 44, width: 44.0 * 6, fit: BoxFit.cover),
    null => SizedBox(
      height: 44,
      width: 44.0 * 6,
      child: Row(
        children: [
          for (final c in const [1, 2, 3, 4, 5, 6])
            Container(width: 44, color: c.isEven ? colors.darkSquare : colors.lightSquare),
        ],
      ),
    ),
  };

  @override
  bool operator ==(Object other) => other is CustomBoardTheme && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CustomBoardTheme($id)';
}

/// The custom piece sets and board themes declared in [kBoardAssetsManifestPath].
@immutable
class const BoardAssetCatalog({
  required final IList<CustomPieceSet> pieceSets,
  required final IList<CustomBoardTheme> boardThemes,
}) {
  static const empty = BoardAssetCatalog(pieceSets: IListConst([]), boardThemes: IListConst([]));

  bool get isEmpty => pieceSets.isEmpty && boardThemes.isEmpty;

  CustomPieceSet? pieceSetById(String id) {
    for (final set in pieceSets) {
      if (set.id == id) return set;
    }
    return null;
  }

  CustomBoardTheme? boardThemeById(String id) {
    for (final theme in boardThemes) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  /// Parses a manifest.
  ///
  /// Throws a [FormatException] if the document is malformed. Individual entries that cannot be
  /// parsed are skipped, so one bad entry does not disable every custom asset.
  factory fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is int && version > kBoardAssetsManifestVersion) {
      _logger.warning(
        'Custom board assets manifest version $version is newer than the supported '
        'version $kBoardAssetsManifestVersion, some entries may be ignored',
      );
    }

    final pieceSets = <CustomPieceSet>[];
    final seenPieceSetIds = <String>{};
    for (final (index, entry) in _readList(json, 'pieceSets').indexed) {
      final set = _parseEntry(entry, 'pieceSets[$index]', _parsePieceSet);
      if (set == null) continue;
      if (!seenPieceSetIds.add(set.id)) {
        _logger.warning('Ignoring duplicate custom piece set id "${set.id}"');
        continue;
      }
      pieceSets.add(set);
    }

    final boardThemes = <CustomBoardTheme>[];
    final seenBoardThemeIds = <String>{};
    for (final (index, entry) in _readList(json, 'boardThemes').indexed) {
      final theme = _parseEntry(entry, 'boardThemes[$index]', _parseBoardTheme);
      if (theme == null) continue;
      if (!seenBoardThemeIds.add(theme.id)) {
        _logger.warning('Ignoring duplicate custom board theme id "${theme.id}"');
        continue;
      }
      boardThemes.add(theme);
    }

    return BoardAssetCatalog(pieceSets: pieceSets.lock, boardThemes: boardThemes.lock);
  }
}

/// Loads and parses the custom board assets manifest.
///
/// Never throws: a missing or malformed manifest yields [BoardAssetCatalog.empty] so the app keeps
/// working with its built-in themes and piece sets.
Future<BoardAssetCatalog> loadBoardAssetCatalog({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  try {
    final raw = await assets.loadString(kBoardAssetsManifestPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The manifest root must be a JSON object');
    }
    final catalog = BoardAssetCatalog.fromJson(decoded);
    _logger.info(
      'Loaded ${catalog.pieceSets.length} custom piece set(s) and '
      '${catalog.boardThemes.length} custom board theme(s)',
    );
    return catalog;
  } catch (e, st) {
    _logger.warning('Could not load $kBoardAssetsManifestPath, using built-in assets only', e, st);
    return BoardAssetCatalog.empty;
  }
}

/// Provides the custom board assets catalog.
///
/// The catalog is loaded once at startup in `init.dart`. [BoardAssetCatalogNotifier.current] is
/// also kept in sync, because preferences are deserialized synchronously and must be able to
/// resolve custom ids.
final boardAssetCatalogProvider = NotifierProvider<BoardAssetCatalogNotifier, BoardAssetCatalog>(
  BoardAssetCatalogNotifier.new,
  name: 'BoardAssetCatalogProvider',
);

class BoardAssetCatalogNotifier() extends Notifier<BoardAssetCatalog> {
  /// The most recently loaded catalog.
  ///
  /// Used where a catalog is needed from synchronous code, such as JSON deserialization of
  /// preferences.
  static BoardAssetCatalog current = BoardAssetCatalog.empty;

  @override
  BoardAssetCatalog build() => current;

  Future<void> load({AssetBundle? bundle}) async {
    final catalog = await loadBoardAssetCatalog(bundle: bundle);
    current = catalog;
    if (ref.mounted) state = catalog;
  }
}

/// A board piece set: either one of the sets built into chessground, or a custom bundled one.
sealed class const PieceSetChoice() {
  /// Used when nothing is stored yet, or when a stored custom set disappeared from the manifest.
  static const fallback = BuiltinPieceSetChoice(PieceSet.cburnett);

  /// Human readable name shown in the settings screen.
  String get label;

  /// The complete set of piece images.
  PieceAssets get assets;

  /// The value stored in preferences.
  String get storageKey;

  /// Name understood by the lichess CDN when exporting a game as a GIF.
  String get shareName;

  /// Resolves a [storageKey], falling back to [fallback] when it is unknown.
  static PieceSetChoice fromStorageKey(String key) {
    if (key.startsWith(_customIdPrefix)) {
      final id = key.substring(_customIdPrefix.length);
      final custom = BoardAssetCatalogNotifier.current.pieceSetById(id);
      if (custom != null) return CustomPieceSetChoice(custom);
      _logger.warning('Unknown custom piece set "$id", falling back to "${fallback.label}"');
      return fallback;
    }
    for (final set in PieceSet.values) {
      if (set.name == key) return BuiltinPieceSetChoice(set);
    }
    _logger.warning('Unknown piece set "$key", falling back to "${fallback.label}"');
    return fallback;
  }
}

/// One of the piece sets built into chessground.
final class const BuiltinPieceSetChoice(final PieceSet set) extends PieceSetChoice {
  @override
  String get label => set.label;

  @override
  PieceAssets get assets => set.assets;

  @override
  String get storageKey => set.name;

  @override
  String get shareName => set.name;

  @override
  bool operator ==(Object other) => other is BuiltinPieceSetChoice && other.set == set;

  @override
  int get hashCode => set.hashCode;

  @override
  String toString() => 'BuiltinPieceSetChoice(${set.name})';
}

/// A piece set bundled with the app.
final class const CustomPieceSetChoice(final CustomPieceSet pieceSet) extends PieceSetChoice {
  @override
  String get label => pieceSet.label;

  @override
  PieceAssets get assets => pieceSet.assets;

  @override
  String get storageKey => '$_customIdPrefix${pieceSet.id}';

  @override
  String get shareName => pieceSet.shareAs;

  @override
  bool operator ==(Object other) =>
      other is CustomPieceSetChoice && other.pieceSet.id == pieceSet.id;

  @override
  int get hashCode => pieceSet.id.hashCode;

  @override
  String toString() => 'CustomPieceSetChoice(${pieceSet.id})';
}

/// Stores a [PieceSetChoice] in preferences as a plain string.
///
/// Built-in sets keep their bare enum name (`cburnett`), so preferences written by previous app
/// versions keep working without a migration. Custom sets are stored as `custom:<id>`.
class const PieceSetChoiceConverter() implements JsonConverter<PieceSetChoice, String> {
  @override
  PieceSetChoice fromJson(String json) => PieceSetChoice.fromStorageKey(json);

  @override
  String toJson(PieceSetChoice object) => object.storageKey;
}

/// Reads a list of entries, tolerating a missing key.
Iterable<Object?> _readList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) throw FormatException('"$key" must be a list');
  return value;
}

/// Parses one entry, skipping it when it is invalid.
T? _parseEntry<T>(
  Object? json,
  String context,
  T Function(Map<String, dynamic> json, String context) parse,
) {
  if (json is! Map<String, dynamic>) {
    _logger.warning('Ignoring $context: expected an object');
    return null;
  }
  try {
    return parse(json, context);
  } on FormatException catch (e) {
    _logger.warning('Ignoring $context: ${e.message}');
    return null;
  }
}

CustomPieceSet _parsePieceSet(Map<String, dynamic> json, String context) {
  final id = _requireId(json, context);
  final label = _requireString(json, 'label', context);
  final dir = _requireString(json, 'dir', context).replaceAll(RegExp(r'/+$'), '');
  final extension = (_optionalString(json, 'extension') ?? 'webp')
      .replaceFirst('.', '')
      .toLowerCase();
  if (!_allowedExtensions.contains(extension)) {
    throw FormatException(
      '"extension" must be one of ${_allowedExtensions.join(', ')} (got "$extension")',
    );
  }

  final rawShareAs = _optionalString(json, 'shareAs') ?? CustomPieceSet.defaultShareAs;
  final shareAs = PieceSet.values.any((set) => set.name == rawShareAs)
      ? rawShareAs
      : CustomPieceSet.defaultShareAs;
  if (shareAs != rawShareAs) {
    _logger.warning('$context: unknown "shareAs" "$rawShareAs", using "$shareAs"');
  }

  return CustomPieceSet(
    id: id,
    label: label,
    shareAs: shareAs,
    assets: {
      for (final kind in PieceKind.values)
        kind: AssetImage('$dir/${pieceAssetFileName(kind)}.$extension'),
    },
  );
}

CustomBoardTheme _parseBoardTheme(Map<String, dynamic> json, String context) {
  final id = _requireId(json, context);
  final label = _requireString(json, 'label', context);
  final lightSquare = _parseColor(json, 'lightSquare', context);
  final darkSquare = _parseColor(json, 'darkSquare', context);
  final texture = _optionalString(json, 'texture');
  final thumbnail = _optionalString(json, 'thumbnail');

  ChessboardBackground background({bool coordinates = false, Side orientation = Side.white}) {
    if (texture == null) {
      return SolidColorChessboardBackground(
        lightSquare: lightSquare,
        darkSquare: darkSquare,
        coordinates: coordinates,
        orientation: orientation,
      );
    }
    return ImageChessboardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      image: AssetImage(texture),
      coordinates: coordinates,
      orientation: orientation,
    );
  }

  return CustomBoardTheme(
    id: id,
    label: label,
    thumbnail: thumbnail != null ? AssetImage(thumbnail) : null,
    colors: ChessboardColorScheme(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      background: background(),
      whiteCoordBackground: background(coordinates: true),
      blackCoordBackground: background(coordinates: true, orientation: Side.black),
      lastMove: HighlightDetails(
        solidColor: _parseColor(json, 'lastMove', context, fallback: '809cc700'),
      ),
      selected: HighlightDetails(
        solidColor: _parseColor(json, 'selected', context, fallback: '6014551e'),
      ),
      validMoves: _parseColor(json, 'validMoves', context, fallback: '4014551e'),
      validPremoves: _parseColor(json, 'validPremoves', context, fallback: '40203085'),
    ),
  );
}

String _requireId(Map<String, dynamic> json, String context) {
  final id = _requireString(json, 'id', context);
  if (!_idRegExp.hasMatch(id)) {
    throw FormatException(
      '"id" may only contain a-z, 0-9, "-" and "_", and must start with a letter or digit '
      '(got "$id")',
    );
  }
  return id;
}

String _requireString(Map<String, dynamic> json, String key, String context) {
  final value = _optionalString(json, key);
  if (value == null) throw FormatException('$context: "$key" is required');
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('"$key" must be a non-empty string');
  }
  return value.trim();
}

/// Parses a hex colour such as `b58863`, `#b58863`, `ffb58863` or `#ffb58863`.
Color _parseColor(Map<String, dynamic> json, String key, String context, {String? fallback}) {
  final raw = _optionalString(json, key) ?? fallback;
  if (raw == null) throw FormatException('"$key" is required');

  var hex = raw.startsWith('#') ? raw.substring(1) : raw;
  if (hex.length == 6) hex = 'ff$hex';
  final value = hex.length == 8 ? int.tryParse(hex, radix: 16) : null;
  if (value == null) {
    throw FormatException(
      '$context: "$key" must be a hex colour such as "b58863" or "ffb58863" (got "$raw")',
    );
  }
  return Color(value);
}
