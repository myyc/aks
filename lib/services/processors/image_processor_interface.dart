import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../models/adjustments.dart';
import '../../models/edit_pipeline.dart';
import '../../models/crop_state.dart';
import '../image_processor.dart';

/// Abstract interface for image processors
/// Allows different implementations (CPU, Vulkan, Metal, etc.)
abstract class ImageProcessorInterface {
  /// Process raw image data with adjustments
  Future<ui.Image> processImage(
    RawPixelData rawData,
    EditPipeline pipeline,
  );
  
  /// Check if this processor is available on the current system
  static Future<bool> isAvailable() async {
    return true; // Base implementation always available
  }
  
  /// Get processor name for debugging/logging
  String get name;
  
  /// Initialize the processor
  Future<void> initialize();
  
  /// Cleanup resources
  void dispose();
  
  /// Process raw pixels with adjustments (implementation-specific)
  Future<Uint8List> processPixels(
    Uint8List pixels,
    int width,
    int height,
    List<Adjustment> adjustments,
  );
}

/// Base implementation with common functionality
abstract class BaseImageProcessor implements ImageProcessorInterface {
  bool _initialized = false;
  
  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await onInitialize();
    _initialized = true;
  }
  
  /// Override this in subclasses for specific initialization
  Future<void> onInitialize();
  
  @override
  Future<ui.Image> processImage(
    RawPixelData rawData,
    EditPipeline pipeline,
  ) async {
    // Ensure processor is initialized
    if (!_initialized) {
      await initialize();
    }
    
    // Apply crop first if present
    RawPixelData workingData = rawData;
    if (pipeline.cropRect != null && 
        (pipeline.cropRect!.left != 0 || pipeline.cropRect!.top != 0 || 
         pipeline.cropRect!.right != 1 || pipeline.cropRect!.bottom != 1)) {
      workingData = _applyCrop(rawData, pipeline.cropRect!);
    }
    
    // Process pixels with adjustments
    final processedPixels = await processPixels(
      Uint8List.fromList(workingData.pixels), // Create copy
      workingData.width,
      workingData.height,
      pipeline.adjustments.toList(),
    );
    
    // Convert to Flutter image
    final buffer = await ui.ImmutableBuffer.fromUint8List(processedPixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: workingData.width,
      height: workingData.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
  
  /// Apply crop to raw pixel data
  static RawPixelData _applyCrop(RawPixelData source, CropRect cropRect) {
    // Calculate the actual pixel coordinates
    final cropLeft = (source.width * cropRect.left).round();
    final cropTop = (source.height * cropRect.top).round();
    final cropRight = (source.width * cropRect.right).round();
    final cropBottom = (source.height * cropRect.bottom).round();
    
    // Calculate new dimensions
    final newWidth = cropRight - cropLeft;
    final newHeight = cropBottom - cropTop;
    
    // Create new pixel array for cropped image
    final croppedPixels = Uint8List(newWidth * newHeight * 3);
    
    // Copy pixels from source to cropped
    int destIndex = 0;
    for (int y = cropTop; y < cropBottom; y++) {
      for (int x = cropLeft; x < cropRight; x++) {
        final sourceIndex = (y * source.width + x) * 3;
        croppedPixels[destIndex++] = source.pixels[sourceIndex];     // R
        croppedPixels[destIndex++] = source.pixels[sourceIndex + 1]; // G
        croppedPixels[destIndex++] = source.pixels[sourceIndex + 2]; // B
      }
    }
    
    return RawPixelData(
      pixels: croppedPixels,
      width: newWidth,
      height: newHeight,
    );
  }
  
  @override
  void dispose() {
    _initialized = false;
  }
}