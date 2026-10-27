# Custom board themes and piece sets

This app renders boards with the [`chessground`](https://pub.dev/packages/chessground) package,
which only needs two things from us:

- a `ChessboardColorScheme` (square colours, highlight colours, and an optional square texture), and
- a `PieceAssets` map of the 12 `PieceKind`s to `AssetImage`s.

Both can point at assets bundled with this app, so custom themes and piece sets need no fork of
`chessground`.

## How it works

Built-in themes and piece sets live in code: `BoardTheme` in
`lib/src/model/settings/board_preferences.dart` and chessground's `PieceSet` enum. Custom ones are
declared in a JSON manifest that is read once at startup, so adding art does not require touching
Dart code.

```
assets/custom/
├── manifest.json
├── boards/
│   ├── my-wood.png          # optional square texture, 1:1 aspect ratio
│   └── my-wood-thumb.jpg     # optional thumbnail for the picker
└── piece_sets/
    └── neon/                 # one directory per set (listed in pubspec.yaml)
        ├── wK.webp  wQ.webp  wR.webp  wB.webp  wN.webp  wP.webp
        └── bK.webp  bQ.webp  bR.webp  bB.webp  bN.webp  bP.webp
```

The loader is `lib/src/model/settings/board_assets.dart`.

## Adding a piece set

1. Create `assets/custom/piece_sets/<id>/` with the 12 images. `<id>` may only contain `a-z`,
   `0-9`, `-` and `_`, and must start with a letter or digit.
2. Add the directory to `pubspec.yaml` under `flutter.assets` — Flutter asset directories are
   **not** recursive, so `assets/custom/` does not cover subdirectories:

   ```yaml
       - assets/custom/
       - assets/custom/piece_sets/<id>/
   ```

3. Declare it in `assets/custom/manifest.json`:

   ```json
   {
     "version": 1,
     "pieceSets": [
       {
         "id": "neon",
         "label": "Neon",
         "dir": "assets/custom/piece_sets/neon",
         "extension": "webp",
         "shareAs": "cburnett"
       }
     ],
     "boardThemes": []
   }
   ```

| Field | Required | Default | Meaning |
| --- | --- | --- | --- |
| `id` | yes | — | Stable identifier. Stored in preferences as `custom:<id>`, so renaming it resets that preference. |
| `label` | yes | — | Name shown in the piece set screen. |
| `dir` | yes | — | Asset directory holding the 12 images. |
| `extension` | no | `webp` | One of `webp`, `png`, `jpg`, `jpeg`. |
| `shareAs` | no | `cburnett` | Built-in set used when sharing a game as a GIF (see limitations). |

Images are decoded at runtime, so **raster formats only — SVG is not supported**. Roughly a
square image at 150-256 px is plenty; chessground draws them at one square per piece.

## Adding a board theme

Add an entry to `boardThemes`:

```json
{
  "id": "my-wood",
  "label": "My Wood",
  "lightSquare": "d8a45b",
  "darkSquare": "9b4d0f",
  "texture": "assets/custom/boards/my-wood.png",
  "thumbnail": "assets/custom/boards/my-wood-thumb.jpg",
  "lastMove": "809cc700",
  "selected": "6014551e",
  "validMoves": "4014551e",
  "validPremoves": "40203085",
  "shareAs": "wood"
}
```

| Field | Required | Default | Meaning |
| --- | --- | --- | --- |
| `id` | yes | — | Stable identifier, stored as `custom:<id>`. |
| `label` | yes | — | Name shown in the board picker. |
| `lightSquare` / `darkSquare` | yes | — | Hex colours, `RRGGBB` or `AARRGGBB`, `#` optional. |
| `texture` | no | — | Square texture drawn over the whole board (`BoxFit.cover`, so use a 1:1 image). Without it the theme is flat squares. |
| `thumbnail` | no | — | Picker thumbnail. Without it a colour swatch is drawn. |
| `lastMove` / `selected` | no | chessground defaults | Highlight colours. |
| `validMoves` / `validPremoves` | no | chessground defaults | Move dot colours. |
| `shareAs` | no | `brown` | Built-in theme used for GIF export. |

Texture and thumbnail files placed in `assets/custom/boards/` are **not** covered by the
`assets/custom/` entry either, so also add `- assets/custom/boards/` to `pubspec.yaml` if you use
textures.

## Failure behaviour

The manifest is parsed defensively, because JSON is not type-checked:

- A missing or malformed manifest logs a warning and yields an empty catalog: the app keeps
  working with built-in assets. A newer-than-supported `version` only logs a warning and is parsed
  on a best-effort basis.
- An individual entry with a bad colour, id, or extension is skipped; the remaining entries still
  load.
- Duplicate ids keep the first entry.
- A preference pointing at a custom set that no longer exists falls back to `cburnett` (pieces) or
  `brown` (boards) instead of failing to start.

## Limitations

- **Sharing a game as a GIF** goes through the lichess CDN, which only knows built-in names, so the
  `shareAs` fallback is used instead of your custom art.
- **The iOS home screen widget** resolves piece images natively and falls back to the default set
  for unknown names, so custom pieces do not appear there.
- **Over-the-board games** explicitly force the `symmetric` piece set.
- Custom art is bundled at build time; changing it requires rebuilding the app.

## Status

Done:

- `assets/custom/manifest.json`, the pubspec entry, and `board_assets.dart` (models, manifest
  parsing, validation, `PieceSetChoice`, and its JSON converter).

Remaining (needs the Flutter SDK to regenerate code and analyse):

- Load the catalog in `init.dart` and precache custom piece images.
- Change `BoardPrefs.pieceSet` / `BoardPrefs.boardTheme` to the choice types, with the
  `PieceSetChoiceConverter` and a `BoardThemeChoiceConverter`.
- List custom entries in `piece_set_screen.dart` and `board_choice_screen.dart`.
- Map custom names to their `shareAs` fallback in `game_share_service.dart` and `app.dart`.
