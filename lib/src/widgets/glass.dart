import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// A pane of frosted glass over whatever is behind it: the background blurred under a white tint
/// that is a little brighter at the top, a 1 px edge lit from above, and a soft shadow.
///
/// A light [blur], a [saturation] boost, a low [tint] and a [bottomGlow] on the rim make it read as
/// liquid glass rather than frosted.
///
/// The look of the home screen's cross menu, shared by the game's player bars.
class const FrostedGlass({
  required final double radius,
  required final Widget child,

  /// Strength of the blur of what is behind the glass.
  final double blur = 14.0,

  /// Opacity of the white tint, in the middle of the pane.
  final double tint = 0.13,

  /// How bright the lit edge is, from 0 (none) to 1.
  final double edge = 1.0,

  /// Opacity of the soft shadow under the pane.
  final double shadow = 0.28,

  /// Saturation of what is behind the glass: above 1, its colours come through more vivid.
  final double saturation = 1.0,

  /// Extra brightness of the rim along the bottom edge. See [GlassBorderPainter.bottomGlow].
  final double bottomGlow = 0.0,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadow),
            blurRadius: 14.0,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: saturation == 1.0
              ? ImageFilter.blur(sigmaX: blur, sigmaY: blur)
              : ImageFilter.compose(
                  outer: ColorFilter.matrix(_saturationMatrix(saturation)),
                  inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                ),
          child: CustomPaint(
            foregroundPainter: GlassBorderPainter(
              radius: radius,
              highlight: Colors.white,
              opacity: edge,
              bottomGlow: bottomGlow,
            ),
            child: DecoratedBox(
              // A sheen: light catches the top of the glass more than the bottom.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: tint + 0.07),
                    Colors.white.withValues(alpha: (tint - 0.05).clamp(0.0, 1.0)),
                  ],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The colour matrix that scales the saturation of a colour by [s] (1 leaves it unchanged).
List<double> _saturationMatrix(double s) {
  // Rec. 709 luma weights.
  const r = 0.2126;
  const g = 0.7152;
  const b = 0.0722;
  final i = 1 - s;
  return [
    i * r + s, i * g, i * b, 0, 0, //
    i * r, i * g + s, i * b, 0, 0, //
    i * r, i * g, i * b + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// A 1 px border that is brighter along the top edge, like light catching a glass edge.
class const GlassBorderPainter({
  required final double radius,
  required final Color highlight,
  required final double opacity,

  /// Extra brightness along the bottom edge, as light passing through the glass catches its far
  /// side: 0 fades the rim out from top to bottom.
  final double bottomGlow = 0.0,
}) extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    final top = highlight.withValues(alpha: 0.55 * opacity);
    final low = highlight.withValues(alpha: 0.08 * opacity);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: bottomGlow == 0.0
            ? [top, low]
            : [top, low, highlight.withValues(alpha: (0.08 + bottomGlow) * opacity)],
        stops: bottomGlow == 0.0 ? null : const [0.0, 0.6, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(GlassBorderPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.highlight != highlight ||
      oldDelegate.opacity != opacity ||
      oldDelegate.bottomGlow != bottomGlow;
}
