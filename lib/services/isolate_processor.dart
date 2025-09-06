import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import '../models/adjustments.dart';
import '../models/edit_pipeline.dart';
import 'image_processor.dart';
import 'optimized_processor.dart';

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

/// Manages image processing in isolates
class IsolateProcessor {
  static Isolate? _isolate;
  static SendPort? _sendPort;
  static bool _isInitialized = false;
  
  /// Initialize the isolate
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, receivePort.sendPort);
    _sendPort = await receivePort.first as SendPort;
    _isInitialized = true;
  }
  
  /// Process image in isolate
  static Future<ui.Image> processImage(
    RawPixelData rawData,
    EditPipeline pipeline,
  ) async {
    // Ensure isolate is initialized
    if (!_isInitialized) {
      await initialize();
    }
    
    final responsePort = ReceivePort();
    
    // Send processing request to isolate
    _sendPort!.send(ProcessingRequest(
      pixels: Uint8List.fromList(rawData.pixels), // Create copy
      width: rawData.width,
      height: rawData.height,
      adjustments: pipeline.adjustments.toList(),
      responsePort: responsePort.sendPort,
    ));
    
    // Wait for response
    final response = await responsePort.first as ProcessingResponse;
    
    if (response.error != null) {
      throw Exception(response.error);
    }
    
    // Convert processed pixels to Flutter image
    final rgbaPixels = response.processedPixels!;
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgbaPixels);
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
  
  /// Dispose of the isolate
  static void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _isInitialized = false;
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
  
  // Copy the processing methods from ImageProcessor
  // These run in the isolate context
  
  static void _applyWhiteBalance(Uint8List pixels, WhiteBalanceAdjustment adj) {
    // Use optimized version with integer math
    OptimizedProcessor.applyWhiteBalanceFast(pixels, adj.temperature, adj.tint);
  }
  
  static void _applyExposure(Uint8List pixels, ExposureAdjustment adj) {
    // Use lookup table version for better performance
    OptimizedProcessor.applyExposureLUT(pixels, adj.value);
  }
  
  static void _applyContrast(Uint8List pixels, ContrastAdjustment adj) {
    // Use lookup table version for better performance
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
  
  static void _applyToneCurve(Uint8List pixels, ToneCurveAdjustment adj) {
    if (adj.isDefault) return;
    
    // Generate lookup tables for each curve
    final rgbLut = _generateCurveLookupTable(adj.rgbCurve);
    final redLut = _generateCurveLookupTable(adj.redCurve);
    final greenLut = _generateCurveLookupTable(adj.greenCurve);
    final blueLut = _generateCurveLookupTable(adj.blueCurve);
    
    // Apply curves using lookup tables
    for (int i = 0; i < pixels.length; i += 3) {
      // Apply per-channel curves first
      int r = redLut[pixels[i]];
      int g = greenLut[pixels[i + 1]];
      int b = blueLut[pixels[i + 2]];
      
      // Then apply RGB curve
      pixels[i] = rgbLut[r];
      pixels[i + 1] = rgbLut[g];
      pixels[i + 2] = rgbLut[b];
    }
  }
  
  static Uint8List _generateCurveLookupTable(List<CurvePoint> points) {
    final lut = Uint8List(256);
    
    if (points.length < 2) {
      // Identity curve
      for (int i = 0; i < 256; i++) {
        lut[i] = i;
      }
      return lut;
    }
    
    // Sort points by x coordinate
    final sortedPoints = List<CurvePoint>.from(points)
      ..sort((a, b) => a.x.compareTo(b.x));
    
    // Handle points before first control point
    for (int i = 0; i <= sortedPoints[0].x; i++) {
      lut[i] = sortedPoints[0].y.round().clamp(0, 255);
    }
    
    // Use linear interpolation for 2 points, Catmull-Rom for 3+
    if (sortedPoints.length == 2) {
      // Simple linear interpolation between two points
      final p1 = sortedPoints[0];
      final p2 = sortedPoints[1];
      for (int x = p1.x.round(); x <= p2.x.round(); x++) {
        if (x >= 0 && x < 256) {
          final t = (x - p1.x) / (p2.x - p1.x);
          final y = p1.y + (p2.y - p1.y) * t;
          lut[x] = y.round().clamp(0, 255);
        }
      }
    } else {
      // Use Catmull-Rom spline for smooth curves with 3+ points
      for (int i = 0; i < sortedPoints.length - 1; i++) {
        final p1 = sortedPoints[i];
        final p2 = sortedPoints[i + 1];
        
        // Get control points for Catmull-Rom
        final p0 = i > 0 ? sortedPoints[i - 1] : p1;
        final p3 = i < sortedPoints.length - 2 ? sortedPoints[i + 2] : p2;
        
        for (int x = p1.x.round(); x <= p2.x.round(); x++) {
          if (x >= 0 && x < 256) {
            final t = (x - p1.x) / (p2.x - p1.x);
            final y = _catmullRom(p0.y, p1.y, p2.y, p3.y, t);
            lut[x] = y.round().clamp(0, 255);
          }
        }
      }
    }
    
    // Handle points after last control point
    for (int i = sortedPoints.last.x.round(); i < 256; i++) {
      lut[i] = sortedPoints.last.y.round().clamp(0, 255);
    }
    
    return lut;
  }
  
  static double _catmullRom(double p0, double p1, double p2, double p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    
    return 0.5 * (
      2 * p1 +
      (-p0 + p2) * t +
      (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
      (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    );
  }
  
  static void _applyBlacksWhites(Uint8List pixels, BlacksWhitesAdjustment adj) {
    if (adj.blacks == 0 && adj.whites == 0) return;
    
    // Calculate black and white points
    // Blacks: -100 crushes blacks (increases black point), +100 lifts blacks
    // Whites: -100 clips whites (decreases white point), +100 extends whites
    final blackPoint = (adj.blacks > 0) 
        ? adj.blacks * 0.5  // Lift blacks up to 50 levels
        : adj.blacks * 0.3;  // Crush blacks down by up to 30 levels
    
    final whitePoint = 255 + ((adj.whites > 0)
        ? adj.whites * 0.5   // Extend whites
        : adj.whites * 0.3); // Clip whites
    
    // Create lookup table for efficiency
    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      // Apply levels adjustment
      double value = i.toDouble();
      
      // Map from [blackPoint, whitePoint] to [0, 255]
      value = ((value - blackPoint) / (whitePoint - blackPoint)) * 255;
      
      lut[i] = _clamp(value.round());
    }
    
    // Apply using lookup table
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = lut[pixels[i]];
    }
  }
  
  static void _applySaturationVibrance(Uint8List pixels, SaturationVibranceAdjustment adj) {
    if (adj.saturation == 0 && adj.vibrance == 0) return;
    
    // Apply saturation using optimized version
    if (adj.saturation != 0) {
      OptimizedProcessor.applySaturationFast(pixels, adj.saturation);
    }
    
    // Apply vibrance if needed (keep original implementation for now)
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