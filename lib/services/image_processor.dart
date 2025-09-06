import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../models/adjustments.dart';
import '../models/edit_pipeline.dart';
import '../models/crop_state.dart';

/// Raw pixel data container
class RawPixelData {
  final Uint8List pixels;  // RGB pixel data
  final int width;
  final int height;
  
  RawPixelData({
    required this.pixels,
    required this.width,
    required this.height,
  });
}

/// Processes raw pixel data with adjustments
class ImageProcessor {
  /// Apply all adjustments from the pipeline to the raw image data
  static Future<ui.Image> processImage(
    RawPixelData rawData,
    EditPipeline pipeline,
  ) async {
    // Don't crop here - cropping is now handled at display/export time
    // Process the full image with adjustments
    final pixels = Uint8List.fromList(rawData.pixels);
    
    // Apply adjustments in order
    for (final adjustment in pipeline.adjustments) {
      if (adjustment is WhiteBalanceAdjustment) {
        _applyWhiteBalance(pixels, adjustment);
      } else if (adjustment is ExposureAdjustment) {
        _applyExposure(pixels, adjustment);
      } else if (adjustment is ContrastAdjustment) {
        _applyContrast(pixels, adjustment);
      } else if (adjustment is HighlightsShadowsAdjustment) {
        _applyHighlightsShadows(pixels, adjustment);
      } else if (adjustment is BlacksWhitesAdjustment) {
        _applyBlacksWhites(pixels, adjustment);
      } else if (adjustment is SaturationVibranceAdjustment) {
        _applySaturationVibrance(pixels, adjustment);
      }
    }
    
    // Convert RGB to RGBA for Flutter
    final rgbaPixels = _convertToRGBA(pixels, rawData.width, rawData.height);
    
    // Create Flutter image
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
  
  /// Apply white balance adjustment
  static void _applyWhiteBalance(Uint8List pixels, WhiteBalanceAdjustment adj) {
    if (adj.temperature == 5500 && adj.tint == 0) return;
    
    // Convert temperature from Kelvin to normalized adjustment
    // 5500K is neutral (daylight)
    // Range: 2000K (very warm) to 10000K (very cool)
    final tempNorm = (adj.temperature - 5500) / 4500; // Normalize to roughly -1 to 1
    
    // Calculate RGB multipliers based on temperature
    // Using a simplified Planckian locus approximation
    double rMult, gMult, bMult;
    
    if (tempNorm < 0) {
      // Warmer (lower temperature) - increase red, decrease blue
      rMult = 1.0 + (-tempNorm * 0.3); // Increase red up to 30%
      gMult = 1.0 + (-tempNorm * 0.05); // Slightly increase green
      bMult = 1.0 - (-tempNorm * 0.4); // Decrease blue up to 40%
    } else {
      // Cooler (higher temperature) - decrease red, increase blue
      rMult = 1.0 - (tempNorm * 0.3); // Decrease red up to 30%
      gMult = 1.0 - (tempNorm * 0.05); // Slightly decrease green
      bMult = 1.0 + (tempNorm * 0.3); // Increase blue up to 30%
    }
    
    // Apply tint adjustment (green-magenta axis)
    // Positive tint = more magenta (less green), negative = more green
    final tintNorm = adj.tint / 150; // Normalize to roughly -1 to 1
    if (tintNorm < 0) {
      // More green
      gMult *= (1.0 - tintNorm * 0.2);
    } else {
      // More magenta (reduce green)
      gMult *= (1.0 - tintNorm * 0.2);
      rMult *= (1.0 + tintNorm * 0.1);
      bMult *= (1.0 + tintNorm * 0.1);
    }
    
    // Apply the multipliers with proper clamping
    for (int i = 0; i < pixels.length; i += 3) {
      pixels[i] = _clamp((pixels[i] * rMult).round());
      pixels[i + 1] = _clamp((pixels[i + 1] * gMult).round());
      pixels[i + 2] = _clamp((pixels[i + 2] * bMult).round());
    }
  }
  
  /// Apply exposure adjustment
  static void _applyExposure(Uint8List pixels, ExposureAdjustment adj) {
    if (adj.value == 0) return;
    
    // Convert stops to multiplier (each stop doubles/halves brightness)
    final factor = math.pow(2, adj.value).toDouble();
    
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = _clamp((pixels[i] * factor).round());
    }
  }
  
  /// Apply contrast adjustment
  static void _applyContrast(Uint8List pixels, ContrastAdjustment adj) {
    if (adj.value == 0) return;
    
    // Contrast formula: newValue = (oldValue - 128) * contrast + 128
    final contrast = (100 + adj.value) / 100;
    
    for (int i = 0; i < pixels.length; i++) {
      final value = pixels[i];
      pixels[i] = _clamp(((value - 128) * contrast + 128).round());
    }
  }
  
  /// Apply highlights and shadows adjustment
  static void _applyHighlightsShadows(Uint8List pixels, HighlightsShadowsAdjustment adj) {
    if (adj.highlights == 0 && adj.shadows == 0) return;
    
    // This is a simplified version - proper implementation would use
    // luminance masks and tone mapping
    for (int i = 0; i < pixels.length; i += 3) {
      // Calculate luminance
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      
      // Apply shadows adjustment (affects dark areas more)
      if (adj.shadows != 0 && luminance < 0.5) {
        final shadowFactor = 1 + (adj.shadows / 100) * (1 - luminance * 2);
        pixels[i] = _clamp((pixels[i] * shadowFactor).round());
        pixels[i + 1] = _clamp((pixels[i + 1] * shadowFactor).round());
        pixels[i + 2] = _clamp((pixels[i + 2] * shadowFactor).round());
      }
      
      // Apply highlights adjustment (affects bright areas more)
      if (adj.highlights != 0 && luminance > 0.5) {
        final highlightFactor = 1 + (adj.highlights / 100) * ((luminance - 0.5) * 2);
        pixels[i] = _clamp((pixels[i] * highlightFactor).round());
        pixels[i + 1] = _clamp((pixels[i + 1] * highlightFactor).round());
        pixels[i + 2] = _clamp((pixels[i + 2] * highlightFactor).round());
      }
    }
  }
  
  /// Apply saturation and vibrance adjustment
  static void _applySaturationVibrance(Uint8List pixels, SaturationVibranceAdjustment adj) {
    if (adj.saturation == 0 && adj.vibrance == 0) return;
    
    for (int i = 0; i < pixels.length; i += 3) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      
      // Convert to HSL for saturation adjustment
      final max = math.max(math.max(r, g), b);
      final min = math.min(math.min(r, g), b);
      final luminance = (max + min) / 2 / 255;
      
      if (adj.saturation != 0) {
        // Simple saturation adjustment
        final gray = (0.299 * r + 0.587 * g + 0.114 * b);
        final satFactor = (100 + adj.saturation) / 100;
        
        pixels[i] = _clamp((gray + (r - gray) * satFactor).round());
        pixels[i + 1] = _clamp((gray + (g - gray) * satFactor).round());
        pixels[i + 2] = _clamp((gray + (b - gray) * satFactor).round());
      }
      
      if (adj.vibrance != 0) {
        // Vibrance affects less-saturated colors more
        final saturation = max == min ? 0 : (max - min) / (255 - (luminance * 255 - 127).abs());
        final vibFactor = (100 + adj.vibrance * (1 - saturation)) / 100;
        
        final gray = (0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2]);
        pixels[i] = _clamp((gray + (pixels[i] - gray) * vibFactor).round());
        pixels[i + 1] = _clamp((gray + (pixels[i + 1] - gray) * vibFactor).round());
        pixels[i + 2] = _clamp((gray + (pixels[i + 2] - gray) * vibFactor).round());
      }
    }
  }
  
  /// Apply blacks and whites point adjustment
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
  
  /// Clamp value between 0 and 255
  static int _clamp(int value) {
    return value.clamp(0, 255);
  }
  
  /// Convert RGB to RGBA
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
  
  /// Apply crop to raw pixel data
  /// Apply crop to an already processed Flutter image (for export)
  static Future<ui.Image> applyCropToImage(ui.Image source, CropRect cropRect) async {
    // Get image dimensions
    final width = source.width;
    final height = source.height;
    
    // Calculate crop rectangle in pixels
    final cropLeft = (width * cropRect.left).round();
    final cropTop = (height * cropRect.top).round();
    final cropRight = (width * cropRect.right).round();
    final cropBottom = (height * cropRect.bottom).round();
    final cropWidth = cropRight - cropLeft;
    final cropHeight = cropBottom - cropTop;
    
    // Create a picture recorder to draw the cropped portion
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    // Draw only the cropped portion of the source image
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTRB(
        cropLeft.toDouble(),
        cropTop.toDouble(),
        cropRight.toDouble(),
        cropBottom.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
      ui.Paint(),
    );
    
    // Convert to image
    final picture = recorder.endRecording();
    return await picture.toImage(cropWidth, cropHeight);
  }
  
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
}