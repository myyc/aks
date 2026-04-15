import 'dart:typed_data';

/// Raw RGB pixel buffer with dimensions.
///
/// Pixels are tightly packed RGB bytes (3 bytes per pixel), in row-major order.
class RawPixelData {
  final Uint8List pixels;
  final int width;
  final int height;

  RawPixelData({
    required this.pixels,
    required this.width,
    required this.height,
  });
}
