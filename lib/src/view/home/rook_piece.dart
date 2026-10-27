import 'dart:ui' show ImageFilter;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Vector rook used when [kRookImageAsset] is null.
const kRookSvgAsset = 'assets/icons/rook.svg';

/// Optional pre-rendered rook, e.g. a rendered 3D PNG or an SVG with its own shading.
///
/// **Swap point:** drop the file in `assets/icons/`, add its directory to `pubspec.yaml`, and set
/// this to its path. When set, the asset is drawn as-is (no tint, no inner highlight), because it
/// carries its own shading; the drop shadow is still applied. A PNG needs transparency, and is
/// shadowed through its alpha channel.
const String? kRookImageAsset = null;

/// The rook drawn on the home cross.
///
/// The vector rook is tinted at runtime, so it works on both the dark centre square and the white
/// arms. Depth comes from a soft drop shadow, a thin rim in [rimColor] (keeps the silhouette
/// legible while it straddles two squares) and a subtle top-down inner highlight.
class const RookPiece({
  required final double size,
  required final Color color,

  /// Colour of the thin outline drawn behind the piece.
  required final Color rimColor,
}) extends StatelessWidget {
  /// Draws the piece, tinted when it is the vector asset.
  Widget _piece(double size, Color tint) {
    const image = kRookImageAsset;
    if (image != null) {
      return Image.asset(image, width: size, height: size, filterQuality: FilterQuality.high);
    }
    return SvgPicture.asset(
      kRookSvgAsset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }

  @override
  Widget build(BuildContext context) {
    const hasShading = kRookImageAsset != null;

    // A blurred, offset copy of the silhouette gives the piece its lift.
    final shadow = Opacity(
      opacity: 0.5,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
        child: Transform.translate(
          offset: const Offset(0, 4),
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
            child: _piece(size, color),
          ),
        ),
      ),
    );

    return SizedBox(
      width: size * 1.22,
      height: size * 1.26,
      child: Stack(
        alignment: Alignment.center,
        children: [
          shadow,
          if (!hasShading) _piece(size * 1.07, rimColor),
          if (hasShading)
            _piece(size, color)
          else
            ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66ffffff), Color(0x00ffffff)],
                stops: [0.0, 0.6],
              ).createShader(bounds),
              child: _piece(size, color),
            ),
        ],
      ),
    );
  }
}
