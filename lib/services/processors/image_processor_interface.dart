import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../models/adjustments.dart';
import '../../models/edit_pipeline.dart';
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
    
    // Process pixels with adjustments
    final processedPixels = await processPixels(
      Uint8List.fromList(rawData.pixels), // Create copy
      rawData.width,
      rawData.height,
      pipeline.adjustments.toList(),
    );
    
    // Convert to Flutter image
    final buffer = await ui.ImmutableBuffer.fromUint8List(processedPixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: rawData.width,
      height: rawData.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }
  
  @override
  void dispose() {
    _initialized = false;
  }
}