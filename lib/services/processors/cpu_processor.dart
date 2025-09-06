import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../models/adjustments.dart';
import '../../models/edit_pipeline.dart';
import '../image_processor.dart';
import '../optimized_processor.dart';
import 'image_processor_interface.dart';

/// CPU-based image processor using isolates
class CpuProcessor extends BaseImageProcessor {
  static Isolate? _isolate;
  static SendPort? _sendPort;
  
  @override
  String get name => 'CPU Processor (Isolate)';
  
  @override
  Future<void> onInitialize() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);
    _sendPort = await receivePort.first as SendPort;
  }
  
  @override
  Future<Uint8List> processPixels(
    Uint8List pixels,
    int width,
    int height,
    List<Adjustment> adjustments,
  ) async {
    final responsePort = ReceivePort();
    
    // Send processing request to isolate
    _sendPort!.send(ProcessingRequest(
      pixels: pixels,
      width: width,
      height: height,
      adjustments: adjustments,
      responsePort: responsePort.sendPort,
    ));
    
    // Wait for response
    final response = await responsePort.first as ProcessingResponse;
    
    if (response.error != null) {
      throw Exception(response.error);
    }
    
    return response.processedPixels!;
  }
  
  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    super.dispose();
  }
  
  /// Isolate entry point - runs in separate thread
  static void _isolateEntryPoint(SendPort sendPort) async {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    // Listen for processing requests
    await for (final message in receivePort) {
      if (message is ProcessingRequest) {
        try {
          // Process the image
          final processedPixels = _processImageInIsolate(
            message.pixels,
            message.width,
            message.height,
            message.adjustments,
          );
          
          // Send response back
          message.responsePort.send(
            ProcessingResponse(processedPixels: processedPixels),
          );
        } catch (e) {
          message.responsePort.send(
            ProcessingResponse(error: e.toString()),
          );
        }
      }
    }
  }
  
  /// Process image pixels with adjustments (runs in isolate)
  static Uint8List _processImageInIsolate(
    Uint8List pixels,
    int width,
    int height,
    List<Adjustment> adjustments,
  ) {
    // Create working copy
    final workingPixels = Uint8List.fromList(pixels);
    
    // Apply each adjustment
    for (final adjustment in adjustments) {
      if (adjustment is WhiteBalanceAdjustment) {
        _applyWhiteBalance(workingPixels, adjustment);
      } else if (adjustment is ExposureAdjustment) {
        _applyExposure(workingPixels, adjustment);
      } else if (adjustment is ContrastAdjustment) {
        _applyContrast(workingPixels, adjustment);
      } else if (adjustment is HighlightsShadowsAdjustment) {
        _applyHighlightsShadows(workingPixels, adjustment);
      } else if (adjustment is BlacksWhitesAdjustment) {
        _applyBlacksWhites(workingPixels, adjustment);
      } else if (adjustment is ToneCurveAdjustment) {
        _applyToneCurve(workingPixels, adjustment);
      } else if (adjustment is SaturationVibranceAdjustment) {
        _applySaturationVibrance(workingPixels, adjustment);
      }
    }
    
    // Convert RGB to RGBA
    return _convertToRGBA(workingPixels, width, height);
  }
  
  // ===== Processing methods (run in isolate) =====
  
  static void _applyWhiteBalance(Uint8List pixels, WhiteBalanceAdjustment adj) {
    OptimizedProcessor.applyWhiteBalanceFast(pixels, adj.temperature, adj.tint);
  }
  
  static void _applyExposure(Uint8List pixels, ExposureAdjustment adj) {
    OptimizedProcessor.applyExposureLUT(pixels, adj.value);
  }
  
  static void _applyContrast(Uint8List pixels, ContrastAdjustment adj) {
    OptimizedProcessor.applyContrastLUT(pixels, adj.value);
  }
  
  static void _applyHighlightsShadows(Uint8List pixels, HighlightsShadowsAdjustment adj) {
    if (adj.highlights == 0 && adj.shadows == 0) return;
    
    for (int i = 0; i < pixels.length; i += 3) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      
      if (adj.shadows != 0 && luminance < 0.5) {
        final shadowFactor = 1 + (adj.shadows / 100) * (1 - luminance * 2);
        pixels[i] = _clamp((pixels[i] * shadowFactor).round());
        pixels[i + 1] = _clamp((pixels[i + 1] * shadowFactor).round());
        pixels[i + 2] = _clamp((pixels[i + 2] * shadowFactor).round());
      }
      
      if (adj.highlights != 0 && luminance > 0.5) {
        final highlightFactor = 1 + (adj.highlights / 100) * ((luminance - 0.5) * 2);
        pixels[i] = _clamp((pixels[i] * highlightFactor).round());
        pixels[i + 1] = _clamp((pixels[i + 1] * highlightFactor).round());
        pixels[i + 2] = _clamp((pixels[i + 2] * highlightFactor).round());
      }
    }
  }
  
  static void _applyBlacksWhites(Uint8List pixels, BlacksWhitesAdjustment adj) {
    if (adj.blacks == 0 && adj.whites == 0) return;
    
    final blackPoint = (adj.blacks > 0) 
        ? adj.blacks * 0.5
        : adj.blacks * 0.3;
    
    final whitePoint = 255 + ((adj.whites > 0)
        ? adj.whites * 0.5
        : adj.whites * 0.3);
    
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      double value = i.toDouble();
      value = ((value - blackPoint) / (whitePoint - blackPoint)) * 255;
      lut[i] = _clamp(value.round());
    }
    
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = lut[pixels[i]];
    }
  }
  
  static void _applyToneCurve(Uint8List pixels, ToneCurveAdjustment adj) {
    if (adj.isDefault) {
      return;
    }
    
    final rgbLut = _generateCurveLookupTable(adj.rgbCurve);
    final redLut = _generateCurveLookupTable(adj.redCurve);
    final greenLut = _generateCurveLookupTable(adj.greenCurve);
    final blueLut = _generateCurveLookupTable(adj.blueCurve);
    
    
    // Apply the tone curves
    for (int i = 0; i < pixels.length; i += 3) {
      int r = redLut[pixels[i]];
      int g = greenLut[pixels[i + 1]];
      int b = blueLut[pixels[i + 2]];
      
      pixels[i] = rgbLut[r];
      pixels[i + 1] = rgbLut[g];
      pixels[i + 2] = rgbLut[b];
    }
    
  }
  
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
    // This prevents unwanted curves when points are on or near the diagonal
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
  
  
  static void _applySaturationVibrance(Uint8List pixels, SaturationVibranceAdjustment adj) {
    if (adj.saturation == 0 && adj.vibrance == 0) return;
    
    if (adj.saturation != 0) {
      OptimizedProcessor.applySaturationFast(pixels, adj.saturation);
    }
    
    if (adj.vibrance != 0) {
      for (int i = 0; i < pixels.length; i += 3) {
        final r = pixels[i];
        final g = pixels[i + 1];
        final b = pixels[i + 2];
        
        final max = [r, g, b].reduce((a, b) => a > b ? a : b);
        final min = [r, g, b].reduce((a, b) => a < b ? a : b);
        final saturation = max == min ? 0.0 : (max - min) / 255.0;
        final vibFactor = (100 + adj.vibrance * (1 - saturation)) / 100;
        
        final gray = (0.299 * r + 0.587 * g + 0.114 * b);
        pixels[i] = _clamp((gray + (r - gray) * vibFactor).round());
        pixels[i + 1] = _clamp((gray + (g - gray) * vibFactor).round());
        pixels[i + 2] = _clamp((gray + (b - gray) * vibFactor).round());
      }
    }
  }
  
  static int _clamp(int value) {
    return value.clamp(0, 255);
  }
  
  static Uint8List _convertToRGBA(Uint8List rgb, int width, int height) {
    final rgbaSize = width * height * 4;
    final rgba = Uint8List(rgbaSize);
    
    int rgbIndex = 0;
    int rgbaIndex = 0;
    for (int i = 0; i < width * height; i++) {
      rgba[rgbaIndex++] = rgb[rgbIndex++]; // R
      rgba[rgbaIndex++] = rgb[rgbIndex++]; // G
      rgba[rgbaIndex++] = rgb[rgbIndex++]; // B
      rgba[rgbaIndex++] = 255; // A
    }
    
    return rgba;
  }
}

/// Data to send to isolate for processing
class ProcessingRequest {
  final Uint8List pixels;
  final int width;
  final int height;
  final List<Adjustment> adjustments;
  final SendPort responsePort;
  
  ProcessingRequest({
    required this.pixels,
    required this.width,
    required this.height,
    required this.adjustments,
    required this.responsePort,
  });
}

/// Response from isolate
class ProcessingResponse {
  final Uint8List? processedPixels;
  final String? error;
  
  ProcessingResponse({this.processedPixels, this.error});
}