import 'dart:typed_data';
import 'dart:math' as math;

/// Optimized image processing using lookup tables and efficient algorithms
class OptimizedProcessor {
  // Lookup tables for common operations
  static Uint8List? _exposureLUT;
  static Uint8List? _contrastLUT;
  static double _lastExposure = 0;
  static double _lastContrast = 0;
  
  /// Generate exposure lookup table
  static Uint8List generateExposureLUT(double exposureValue) {
    final lut = Uint8List(256);
    final factor = math.pow(2, exposureValue).toDouble();
    
    for (int i = 0; i < 256; i++) {
      lut[i] = (i * factor).round().clamp(0, 255);
    }
    
    return lut;
  }
  
  /// Generate contrast lookup table
  static Uint8List generateContrastLUT(double contrastValue) {
    final lut = Uint8List(256);
    final contrast = (100 + contrastValue) / 100;
    
    for (int i = 0; i < 256; i++) {
      lut[i] = ((i - 128) * contrast + 128).round().clamp(0, 255);
    }
    
    return lut;
  }
  
  /// Apply exposure using lookup table (much faster than per-pixel calculation)
  static void applyExposureLUT(Uint8List pixels, double exposureValue) {
    if (exposureValue == 0) return;
    
    // Regenerate LUT only if exposure changed
    if (_exposureLUT == null || _lastExposure != exposureValue) {
      _exposureLUT = generateExposureLUT(exposureValue);
      _lastExposure = exposureValue;
    }
    
    final lut = _exposureLUT!;
    
    // Apply LUT - much faster than calculating for each pixel
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = lut[pixels[i]];
    }
  }
  
  /// Apply contrast using lookup table
  static void applyContrastLUT(Uint8List pixels, double contrastValue) {
    if (contrastValue == 0) return;
    
    // Regenerate LUT only if contrast changed
    if (_contrastLUT == null || _lastContrast != contrastValue) {
      _contrastLUT = generateContrastLUT(contrastValue);
      _lastContrast = contrastValue;
    }
    
    final lut = _contrastLUT!;
    
    // Apply LUT
    for (int i = 0; i < pixels.length; i++) {
      pixels[i] = lut[pixels[i]];
    }
  }
  
  /// Process pixels in chunks to avoid memory spikes
  static void processInChunks(
    Uint8List pixels,
    int chunkSize,
    void Function(Uint8List chunk, int offset) processor,
  ) {
    final totalPixels = pixels.length;
    
    for (int offset = 0; offset < totalPixels; offset += chunkSize) {
      final end = math.min(offset + chunkSize, totalPixels);
      final chunkLength = end - offset;
      
      // Create a view into the pixels array for this chunk
      final chunk = Uint8List.view(
        pixels.buffer,
        pixels.offsetInBytes + offset,
        chunkLength,
      );
      
      processor(chunk, offset);
    }
  }
  
  /// Optimized white balance using Kelvin temperature
  static void applyWhiteBalanceFast(Uint8List pixels, double temperature, double tint) {
    if (temperature == 5500 && tint == 0) return; // Already at default
    
    // Convert Kelvin temperature to RGB multipliers
    // Reference: 5500K is neutral daylight
    // Lower temps (2000-5500K) are warmer (more red/yellow)
    // Higher temps (5500-10000K) are cooler (more blue)
    
    // Normalize temperature to -1 to 1 range (5500K = 0)
    final tempNorm = (temperature - 5500) / 4500;
    
    // Calculate RGB factors based on temperature
    // Warmer = more red, less blue; Cooler = less red, more blue
    final tempFactorR = ((1 - tempNorm * 0.3) * 256).round();
    final tempFactorB = ((1 + tempNorm * 0.3) * 256).round();
    
    // Tint affects green-magenta axis (-150 to 150)
    final tintNorm = tint / 150;
    final tintFactor = ((1 + tintNorm * 0.2) * 256).round();
    
    for (int i = 0; i < pixels.length; i += 3) {
      // Use integer math for speed
      pixels[i] = ((pixels[i] * tempFactorR) >> 8).clamp(0, 255);
      pixels[i + 1] = ((pixels[i + 1] * tintFactor) >> 8).clamp(0, 255);
      pixels[i + 2] = ((pixels[i + 2] * tempFactorB) >> 8).clamp(0, 255);
    }
  }
  
  /// Optimized saturation using integer math
  static void applySaturationFast(Uint8List pixels, double saturation) {
    if (saturation == 0) return;
    
    // Pre-calculate factor as integer
    final satFactor = ((100 + saturation) * 256 ~/ 100);
    
    // Pre-calculate luminance weights as integers
    const rWeight = 77;  // 0.299 * 256
    const gWeight = 150; // 0.587 * 256
    const bWeight = 29;  // 0.114 * 256
    
    for (int i = 0; i < pixels.length; i += 3) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      
      // Calculate gray value using integer math
      final gray = (r * rWeight + g * gWeight + b * bWeight) >> 8;
      
      // Apply saturation using integer math
      pixels[i] = ((gray + ((r - gray) * satFactor >> 8))).clamp(0, 255);
      pixels[i + 1] = ((gray + ((g - gray) * satFactor >> 8))).clamp(0, 255);
      pixels[i + 2] = ((gray + ((b - gray) * satFactor >> 8))).clamp(0, 255);
    }
  }
  
  /// Generate highlights/shadows lookup tables (returns factor * 256 for integer math)
  static (Uint16List, Uint16List) generateHighlightsShadowsLUTs(double highlights, double shadows) {
    final highlightsLUT = Uint16List(256);
    final shadowsLUT = Uint16List(256);
    
    for (int i = 0; i < 256; i++) {
      final luminance = i / 255.0;
      
      // Shadows: affect values below 0.5 luminance
      if (shadows != 0 && luminance < 0.5) {
        final shadowFactor = 1 + (shadows / 100) * (1 - luminance * 2);
        // Store as factor * 256 for integer multiplication
        shadowsLUT[i] = (shadowFactor * 256).round().clamp(0, 512);
      } else {
        shadowsLUT[i] = 256; // Identity factor
      }
      
      // Highlights: affect values above 0.5 luminance
      if (highlights != 0 && luminance > 0.5) {
        final highlightFactor = 1 + (highlights / 100) * ((luminance - 0.5) * 2);
        // Store as factor * 256 for integer multiplication
        highlightsLUT[i] = (highlightFactor * 256).round().clamp(0, 512);
      } else {
        highlightsLUT[i] = 256; // Identity factor
      }
    }
    
    return (highlightsLUT, shadowsLUT);
  }
  
  /// Apply highlights and shadows using pre-calculated LUTs
  static void applyHighlightsShadowsLUT(Uint8List pixels, double highlights, double shadows) {
    if (highlights == 0 && shadows == 0) return;
    
    // Generate combined LUTs
    final (highlightsLUT, shadowsLUT) = generateHighlightsShadowsLUTs(highlights, shadows);
    
    // Pre-calculate luminance weights as integers for speed
    const rWeight = 77;  // 0.299 * 256
    const gWeight = 150; // 0.587 * 256
    const bWeight = 29;  // 0.114 * 256
    
    for (int i = 0; i < pixels.length; i += 3) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      
      // Calculate luminance using integer math
      final lum = ((r * rWeight + g * gWeight + b * bWeight) >> 8).clamp(0, 255);
      
      // Get adjustment factors from LUTs
      final highlightFactor = highlightsLUT[lum];
      final shadowFactor = shadowsLUT[lum];
      
      // Apply the stronger effect (highlights or shadows)
      if (lum < 128) {
        // Shadow region - apply shadow adjustment
        pixels[i] = ((r * shadowFactor) >> 8).clamp(0, 255);
        pixels[i + 1] = ((g * shadowFactor) >> 8).clamp(0, 255);
        pixels[i + 2] = ((b * shadowFactor) >> 8).clamp(0, 255);
      } else {
        // Highlight region - apply highlight adjustment
        pixels[i] = ((r * highlightFactor) >> 8).clamp(0, 255);
        pixels[i + 1] = ((g * highlightFactor) >> 8).clamp(0, 255);
        pixels[i + 2] = ((b * highlightFactor) >> 8).clamp(0, 255);
      }
    }
  }
  
  /// Optimized vibrance using integer math
  static void applyVibranceFast(Uint8List pixels, double vibrance) {
    if (vibrance == 0) return;
    
    // Pre-calculate luminance weights
    const rWeight = 77;  // 0.299 * 256
    const gWeight = 150; // 0.587 * 256
    const bWeight = 29;  // 0.114 * 256
    
    // Pre-calculate vibrance factor scale
    final vibScale = (vibrance * 256 / 100).round();
    
    for (int i = 0; i < pixels.length; i += 3) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      
      // Fast min/max using conditionals (faster than array operations)
      int max = r;
      int min = r;
      if (g > max) max = g;
      if (b > max) max = b;
      if (g < min) min = g;
      if (b < min) min = b;
      
      // Calculate saturation (0-255 range)
      final sat = max - min;
      
      // Calculate vibrance factor based on current saturation
      // Less saturated colors get more boost
      final vibFactor = 256 + ((256 - sat) * vibScale >> 8);
      
      // Calculate gray value
      final gray = (r * rWeight + g * gWeight + b * bWeight) >> 8;
      
      // Apply vibrance
      pixels[i] = ((gray + ((r - gray) * vibFactor >> 8))).clamp(0, 255);
      pixels[i + 1] = ((gray + ((g - gray) * vibFactor >> 8))).clamp(0, 255);
      pixels[i + 2] = ((gray + ((b - gray) * vibFactor >> 8))).clamp(0, 255);
    }
  }
  
  /// Clear cached lookup tables
  static void clearCache() {
    _exposureLUT = null;
    _contrastLUT = null;
    _lastExposure = 0;
    _lastContrast = 0;
  }
}