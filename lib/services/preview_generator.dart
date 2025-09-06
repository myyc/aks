import 'dart:typed_data';
import 'dart:math' as math;
import 'image_processor.dart';

/// Generates preview-sized versions of images for faster processing
class PreviewGenerator {
  static const int MAX_PREVIEW_SIZE = 1024;
  
  /// Generate a preview version of the raw pixel data
  static RawPixelData generatePreview(RawPixelData fullData) {
    // Calculate scale factor
    final maxDimension = math.max(fullData.width, fullData.height);
    if (maxDimension <= MAX_PREVIEW_SIZE) {
      // Already small enough, return as-is
      return fullData;
    }
    
    final scale = MAX_PREVIEW_SIZE / maxDimension;
    final previewWidth = (fullData.width * scale).round();
    final previewHeight = (fullData.height * scale).round();
    
    // Downsample using simple nearest neighbor for speed
    final previewPixels = _downsample(
      fullData.pixels,
      fullData.width,
      fullData.height,
      previewWidth,
      previewHeight,
    );
    
    return RawPixelData(
      pixels: previewPixels,
      width: previewWidth,
      height: previewHeight,
    );
  }
  
  /// Downsample image pixels using nearest neighbor
  static Uint8List _downsample(
    Uint8List sourcePixels,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final targetPixels = Uint8List(targetWidth * targetHeight * 3);
    
    final xRatio = sourceWidth / targetWidth;
    final yRatio = sourceHeight / targetHeight;
    
    int targetIndex = 0;
    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        // Find corresponding source pixel
        final sourceX = (x * xRatio).floor();
        final sourceY = (y * yRatio).floor();
        final sourceIndex = (sourceY * sourceWidth + sourceX) * 3;
        
        // Copy RGB values
        targetPixels[targetIndex++] = sourcePixels[sourceIndex];
        targetPixels[targetIndex++] = sourcePixels[sourceIndex + 1];
        targetPixels[targetIndex++] = sourcePixels[sourceIndex + 2];
      }
    }
    
    return targetPixels;
  }
  
  /// Calculate if we should use preview based on zoom level
  static bool shouldUsePreview(double zoomLevel) {
    // Use preview when zoomed out (< 100% zoom)
    return zoomLevel < 1.0;
  }
}