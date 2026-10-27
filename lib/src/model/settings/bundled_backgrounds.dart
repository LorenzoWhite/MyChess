import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:material_ui/material_ui.dart';

/// A background image that is bundled with the app, as opposed to one picked by the user.
///
/// The values that the picker normally derives from the image at selection time (`seedColor`,
/// `meanLuminance`, and the image size) are declared here, so a bundled background can be applied
/// without decoding the image first.
@immutable
class const BundledBackground({
  /// Stable identifier, only used to tell bundled backgrounds apart.
  required final String id,

  /// Human readable name shown in the background picker.
  required final String label,

  /// Path of the image in the app bundle.
  required final String assetPath,

  /// Colour the app theme is derived from while this background is active.
  ///
  /// Everything visible over the image (surfaces, text, accents) uses this seed, so it should be
  /// picked from the artwork rather than being arbitrary.
  required final Color seedColor,

  /// Mean relative luminance of the image, between 0 and 1.
  ///
  /// Drives the tint that is laid over the image to keep the interface readable.
  required final double meanLuminance,

  /// Width of the image, in pixels.
  required final double width,

  /// Height of the image, in pixels.
  required final double height,

  /// Whether the image is blurred. A blur can help readability behind dense screens.
  final bool isBlurred = false,
}) {
  /// Builds the preference value for this background, for the given screen [viewport].
  BackgroundImage toBackgroundImage({required Size viewport}) => BackgroundImage(
    path: assetPath,
    isBundled: true,
    // Bundled images are not panned or zoomed, so no transform is applied on top of the fit.
    transform: Matrix4.identity(),
    isBlurred: isBlurred,
    seedColor: seedColor,
    meanLuminance: meanLuminance,
    width: width,
    height: height,
    viewportWidth: viewport.width,
    viewportHeight: viewport.height,
  );
}

/// Backgrounds bundled with the app and offered in the background picker.
const kBundledBackgrounds = <BundledBackground>[
  BundledBackground(
    id: 'futuristic',
    label: 'Futuristic',
    assetPath: 'assets/backgrounds/futuristic.jpg',
    // Muted indigo taken from the artwork's dominant purple, lifted in saturation so that the
    // derived theme has a usable accent colour.
    seedColor: Color(0xff503e98),
    meanLuminance: 0.036,
    width: 1080,
    height: 1935,
    isBlurred: true,
  ),
];
