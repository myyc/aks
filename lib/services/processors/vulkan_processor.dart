import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import '../../models/adjustments.dart';
import '../../models/edit_pipeline.dart';
import '../../models/crop_state.dart';
import '../image_processor.dart';
import 'image_processor_interface.dart';
import 'vulkan/vulkan_bindings.dart';
import 'cpu_processor.dart';

/// GPU-accelerated image processor using Vulkan
class VulkanProcessor extends BaseImageProcessor {
  static bool? _isAvailable;
  bool _initialized = false;
  
  @override
  String get name => 'Vulkan GPU Processor';
  
  /// Check if Vulkan is available on this system
  static Future<bool> isAvailable() async {
    // Only available on Linux and Windows
    if (!Platform.isLinux && !Platform.isWindows) {
      return false;
    }
    
    // Cache the availability check
    _isAvailable ??= VulkanBindings.isAvailable();
    return _isAvailable!;
  }
  
  @override
  Future<void> onInitialize() async {
    if (!VulkanBindings.initialize()) {
      throw Exception('Failed to initialize Vulkan');
    }
    _initialized = true;
  }
  
  @override
  Future<ui.Image> processImage(
    RawPixelData rawData,
    EditPipeline pipeline,
  ) async {
    // Ensure processor is initialized
    if (!_initialized) {
      await initialize();
    }
    
    // Check if we have a crop to apply
    final hasCrop = pipeline.cropRect != null && 
        (pipeline.cropRect!.left != 0 || pipeline.cropRect!.top != 0 || 
         pipeline.cropRect!.right != 1 || pipeline.cropRect!.bottom != 1);
    
    // If we have crop, use the GPU cropping version
    if (hasCrop) {
      // Generate tone curve LUTs if present
      Uint8List? rgbLut;
      Uint8List? redLut;
      Uint8List? greenLut;
      Uint8List? blueLut;
      
      // Check for tone curve adjustments
      for (final adjustment in pipeline.adjustments) {
        if (adjustment is ToneCurveAdjustment) {
          rgbLut = _generateCurveLookupTable(adjustment.rgbCurve);
          redLut = _generateCurveLookupTable(adjustment.redCurve);
          greenLut = _generateCurveLookupTable(adjustment.greenCurve);
          blueLut = _generateCurveLookupTable(adjustment.blueCurve);
          break;
        }
      }
      
      // Pack adjustments with crop parameters
      final packedAdjustments = _packAdjustmentsWithCrop(
        pipeline.adjustments.toList(), 
        pipeline.cropRect!,
        rawData.width.toDouble(),
        rawData.height.toDouble(),
        hasToneCurves: rgbLut != null,
      );
      
      // Process on GPU with cropping
      print('VulkanProcessor: Processing with crop: ${pipeline.cropRect!.left}, ${pipeline.cropRect!.top}, ${pipeline.cropRect!.right}, ${pipeline.cropRect!.bottom}');
      print('VulkanProcessor: Input dimensions: ${rawData.width}x${rawData.height}');
      
      final result = VulkanBindings.processImageWithCrop(
        Uint8List.fromList(rawData.pixels),
        rawData.width,
        rawData.height,
        packedAdjustments,
        pipeline.cropRect!.left,
        pipeline.cropRect!.top,
        pipeline.cropRect!.right,
        pipeline.cropRect!.bottom,
        rgbLut: rgbLut,
        redLut: redLut,
        greenLut: greenLut,
        blueLut: blueLut,
      );
      
      if (result == null) {
        throw Exception('Vulkan processing with crop failed');
      }
      
      print('VulkanProcessor: Output dimensions: ${result.width}x${result.height}');
      
      // Convert to Flutter image
      final buffer = await ui.ImmutableBuffer.fromUint8List(result.pixels);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: result.width,
        height: result.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frameInfo = await codec.getNextFrame();
      return frameInfo.image;
    } else {
      // No crop, use regular processing
      final processedPixels = await processPixels(
        Uint8List.fromList(rawData.pixels),
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
  }
  
  @override
  Future<Uint8List> processPixels(
    Uint8List pixels,
    int width,
    int height,
    List<Adjustment> adjustments,
  ) async {
    // Generate tone curve LUTs if present
    Uint8List? rgbLut;
    Uint8List? redLut;
    Uint8List? greenLut;
    Uint8List? blueLut;
    
    // Check for tone curve adjustments
    for (final adjustment in adjustments) {
      if (adjustment is ToneCurveAdjustment) {
        rgbLut = _generateCurveLookupTable(adjustment.rgbCurve);
        redLut = _generateCurveLookupTable(adjustment.redCurve);
        greenLut = _generateCurveLookupTable(adjustment.greenCurve);
        blueLut = _generateCurveLookupTable(adjustment.blueCurve);
        break;
      }
    }
    
    // Pack adjustments into a float array for GPU
    final packedAdjustments = _packAdjustments(adjustments, hasToneCurves: rgbLut != null);
    
    // Process on GPU with tone curves
    final result = VulkanBindings.processImage(
      pixels,
      width,
      height,
      packedAdjustments,
      rgbLut: rgbLut,
      redLut: redLut,
      greenLut: greenLut,
      blueLut: blueLut,
    );
    
    if (result == null) {
      throw Exception('Vulkan processing failed');
    }
    
    return result;
  }
  
  /// Generate tone curve lookup table from control points
  static Uint8List _generateCurveLookupTable(List<CurvePoint> points) {
    final lut = Uint8List(256);
    
    // Handle empty or insufficient points - return identity
    if (points.length < 2) {
      for (int i = 0; i < 256; i++) {
        lut[i] = i;
      }
      return lut;
    }
    
    final sortedPoints = List<CurvePoint>.from(points)
      ..sort((a, b) => a.x.compareTo(b.x));
    
    // Special case: Check for identity curve (default state)
    if (sortedPoints.length == 2 && 
        sortedPoints[0].x == 0 && sortedPoints[0].y == 0 &&
        sortedPoints[1].x == 255 && sortedPoints[1].y == 255) {
      // Perfect identity mapping
      for (int i = 0; i < 256; i++) {
        lut[i] = i;
      }
      return lut;
    }
    
    // Fill the beginning up to the first point
    for (int i = 0; i < sortedPoints[0].x.round() && i < 256; i++) {
      lut[i] = sortedPoints[0].y.round().clamp(0, 255);
    }
    
    // Use linear interpolation between all points for predictable behavior
    for (int i = 0; i < sortedPoints.length - 1; i++) {
      final p1 = sortedPoints[i];
      final p2 = sortedPoints[i + 1];
      final x1 = p1.x.round().clamp(0, 255);
      final x2 = p2.x.round().clamp(0, 255);
      
      for (int x = x1; x <= x2 && x < 256; x++) {
        if (p2.x - p1.x != 0) {
          // Linear interpolation between adjacent points
          final t = (x - p1.x) / (p2.x - p1.x);
          final y = p1.y + (p2.y - p1.y) * t;
          lut[x] = y.round().clamp(0, 255);
        } else {
          // Same x coordinate - use first point's y value
          lut[x] = p1.y.round().clamp(0, 255);
        }
      }
    }
    
    // Fill the end from the last point
    final lastX = sortedPoints.last.x.round().clamp(0, 255);
    for (int i = lastX + 1; i < 256; i++) {
      lut[i] = sortedPoints.last.y.round().clamp(0, 255);
    }
    
    return lut;
  }
  
  /// Pack adjustments into a float array for shader uniforms
  Float32List _packAdjustments(List<Adjustment> adjustments, {bool hasToneCurves = false}) {
    // Pack adjustment parameters to match shader uniform structure
    // The C code expects exactly these parameters in this order:
    // temperature, tint, exposure, contrast, highlights, shadows,
    // blacks, whites, saturation, vibrance, toneCurveEnabled, padding[3]
    
    double temperature = 5500.0;  // Default neutral temperature
    double tint = 0.0;
    double exposure = 0.0;
    double contrast = 0.0;
    double highlights = 0.0;
    double shadows = 0.0;
    double blacks = 0.0;
    double whites = 0.0;
    double saturation = 0.0;
    double vibrance = 0.0;
    
    // Extract values from adjustments
    for (final adjustment in adjustments) {
      if (adjustment is WhiteBalanceAdjustment) {
        temperature = adjustment.temperature;
        tint = adjustment.tint;
      } else if (adjustment is ExposureAdjustment) {
        exposure = adjustment.value;
      } else if (adjustment is ContrastAdjustment) {
        contrast = adjustment.value;
      } else if (adjustment is HighlightsShadowsAdjustment) {
        highlights = adjustment.highlights;
        shadows = adjustment.shadows;
      } else if (adjustment is BlacksWhitesAdjustment) {
        blacks = adjustment.blacks;
        whites = adjustment.whites;
      } else if (adjustment is SaturationVibranceAdjustment) {
        saturation = adjustment.saturation;
        vibrance = adjustment.vibrance;
      }
    }
    
    // Pack into array matching shader uniform structure (must be 16 floats)
    return Float32List.fromList([
      temperature,
      tint,
      exposure,
      contrast,
      highlights,
      shadows,
      blacks,
      whites,
      saturation,
      vibrance,
      hasToneCurves ? 1.0 : 0.0,  // toneCurveEnabled
      0.0,  // padding
      0.0,  // padding
      0.0,  // padding
      0.0,  // padding
      0.0,  // padding to make 16 floats (64 bytes)
    ]);
  }
  
  /// Pack adjustments with crop parameters for GPU processing
  Float32List _packAdjustmentsWithCrop(
    List<Adjustment> adjustments,
    CropRect cropRect,
    double imageWidth,
    double imageHeight,
    {bool hasToneCurves = false}
  ) {
    // Pack adjustment parameters to match shader uniform structure with crop
    double temperature = 5500.0;  // Default neutral temperature
    double tint = 0.0;
    double exposure = 0.0;
    double contrast = 0.0;
    double highlights = 0.0;
    double shadows = 0.0;
    double blacks = 0.0;
    double whites = 0.0;
    double saturation = 0.0;
    double vibrance = 0.0;
    
    // Extract values from adjustments
    for (final adjustment in adjustments) {
      if (adjustment is WhiteBalanceAdjustment) {
        temperature = adjustment.temperature;
        tint = adjustment.tint;
      } else if (adjustment is ExposureAdjustment) {
        exposure = adjustment.value;
      } else if (adjustment is ContrastAdjustment) {
        contrast = adjustment.value;
      } else if (adjustment is HighlightsShadowsAdjustment) {
        highlights = adjustment.highlights;
        shadows = adjustment.shadows;
      } else if (adjustment is BlacksWhitesAdjustment) {
        blacks = adjustment.blacks;
        whites = adjustment.whites;
      } else if (adjustment is SaturationVibranceAdjustment) {
        saturation = adjustment.saturation;
        vibrance = adjustment.vibrance;
      }
    }
    
    // Pack into array matching shader uniform structure with crop (18 floats)
    return Float32List.fromList([
      temperature,
      tint,
      exposure,
      contrast,
      highlights,
      shadows,
      blacks,
      whites,
      saturation,
      vibrance,
      hasToneCurves ? 1.0 : 0.0,  // toneCurveEnabled
      imageWidth,
      imageHeight,
      0.0,  // padding
      cropRect.left,
      cropRect.top,
      cropRect.right,
      cropRect.bottom,
    ]);
  }
  
  @override
  void dispose() {
    // Don't dispose VulkanBindings - keep it alive for the lifetime of the app
    // VulkanBindings.dispose();
    // _isAvailable = null;  // Clear the availability cache
    super.dispose();
  }
}