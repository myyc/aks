import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;

/// Service for manipulating images (resize, frame, etc.)
class ImageManipulationService {
  
  /// Resize image by percentage
  static Future<ui.Image> resizeByPercentage(
    ui.Image image,
    double percentage, // 0.0 to 1.0
  ) async {
    if (percentage == 1.0) return image;
    
    final newWidth = (image.width * percentage).round();
    final newHeight = (image.height * percentage).round();
    
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    // Draw scaled image
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
    final src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = ui.Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble());
    
    canvas.drawImageRect(image, src, dst, paint);
    
    final picture = recorder.endRecording();
    return await picture.toImage(newWidth, newHeight);
  }
  
  /// Pad image to square with specified color
  static Future<ui.Image> padToSquare(
    ui.Image image,
    ui.Color backgroundColor,
  ) async {
    if (image.width == image.height) return image;
    
    final size = math.max(image.width, image.height);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    // Fill background
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = backgroundColor,
    );
    
    // Center the image
    final offsetX = (size - image.width) / 2;
    final offsetY = (size - image.height) / 2;
    
    canvas.drawImage(image, ui.Offset(offsetX, offsetY), ui.Paint());
    
    final picture = recorder.endRecording();
    return await picture.toImage(size, size);
  }
  
  /// Add uniform border to image
  static Future<ui.Image> addUniformBorder(
    ui.Image image,
    int borderWidth,
    ui.Color borderColor,
  ) async {
    if (borderWidth <= 0) return image;
    
    final newWidth = image.width + (borderWidth * 2);
    final newHeight = image.height + (borderWidth * 2);
    
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    // Draw border (background)
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, newWidth.toDouble(), newHeight.toDouble()),
      ui.Paint()..color = borderColor,
    );
    
    // Draw image on top
    canvas.drawImage(
      image, 
      ui.Offset(borderWidth.toDouble(), borderWidth.toDouble()), 
      ui.Paint(),
    );
    
    final picture = recorder.endRecording();
    return await picture.toImage(newWidth, newHeight);
  }
  
  /// Resize to fit within max dimensions (maintains aspect ratio)
  static Future<ui.Image> resizeToFit(
    ui.Image image,
    int maxWidth,
    int maxHeight,
  ) async {
    if (image.width <= maxWidth && image.height <= maxHeight) {
      return image;
    }
    
    // Calculate scale to fit
    final scaleX = maxWidth / image.width;
    final scaleY = maxHeight / image.height;
    final scale = math.min(scaleX, scaleY);
    
    return resizeByPercentage(image, scale);
  }
  
  /// Apply all transformations in order
  static Future<ui.Image> applyTransformations(
    ui.Image image, {
    double? resizePercentage,
    bool padToSquare = false,
    ui.Color padColor = const ui.Color(0xFF000000),
    int borderWidth = 0,
    ui.Color borderColor = const ui.Color(0xFF000000),
  }) async {
    ui.Image result = image;
    
    // 1. Resize if needed
    if (resizePercentage != null && resizePercentage != 1.0) {
      result = await resizeByPercentage(result, resizePercentage);
    }
    
    // 2. Pad to square if needed
    if (padToSquare) {
      result = await ImageManipulationService.padToSquare(result, padColor);
    }
    
    // 3. Add border if needed
    if (borderWidth > 0) {
      result = await addUniformBorder(result, borderWidth, borderColor);
    }
    
    return result;
  }
}