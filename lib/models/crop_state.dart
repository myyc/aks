import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Represents the crop region in normalized coordinates (0.0 to 1.0)
class CropRect {
  final double left;
  final double top;
  final double right;
  final double bottom;
  
  const CropRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
  
  factory CropRect.full() {
    return const CropRect(
      left: 0.0,
      top: 0.0,
      right: 1.0,
      bottom: 1.0,
    );
  }
  
  double get width => right - left;
  double get height => bottom - top;
  double get aspectRatio => width / height;
  
  /// Convert to pixel coordinates
  Rect toPixelRect(double imageWidth, double imageHeight) {
    return Rect.fromLTRB(
      left * imageWidth,
      top * imageHeight,
      right * imageWidth,
      bottom * imageHeight,
    );
  }
  
  /// Create from pixel coordinates
  factory CropRect.fromPixelRect(Rect rect, double imageWidth, double imageHeight) {
    return CropRect(
      left: rect.left / imageWidth,
      top: rect.top / imageHeight,
      right: rect.right / imageWidth,
      bottom: rect.bottom / imageHeight,
    );
  }
  
  CropRect copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    return CropRect(
      left: left ?? this.left,
      top: top ?? this.top,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
  
  factory CropRect.fromJson(Map<String, dynamic> json) {
    return CropRect(
      left: (json['left'] ?? 0.0).toDouble(),
      top: (json['top'] ?? 0.0).toDouble(),
      right: (json['right'] ?? 1.0).toDouble(),
      bottom: (json['bottom'] ?? 1.0).toDouble(),
    );
  }
  
  @override
  String toString() {
    return 'CropRect(left: $left, top: $top, right: $right, bottom: $bottom)';
  }
}

/// Preset aspect ratios for cropping - each has portrait and landscape versions
enum AspectRatioPreset {
  free,            // Free crop
  square,          // 1:1 - Square
  format67,        // 6×7 Medium format (6:7 portrait / 7:6 landscape)
  format57,        // 5×7 Print (5:7 portrait / 7:5 landscape)
  format810,       // 8×10 Large format (4:5 portrait / 5:4 landscape)
  format645,       // 6×4.5 Medium format (3:4 portrait / 4:3 landscape)
  format35mm,      // 35mm Film (2:3 portrait / 3:2 landscape)
  format169,       // 16:9 Video / 9:16 Story (9:16 portrait / 16:9 landscape)
  cinemascope,     // Cinemascope (1:2.35 portrait / 2.35:1 landscape)
  xpan,            // Xpan Panoramic (24:65 portrait / 65:24 landscape)
}

extension AspectRatioPresetExtension on AspectRatioPreset {
  // Get ratio based on orientation
  double? getRatioWithOrientation(bool isPortrait) {
    final baseRatio = ratio;
    if (baseRatio == null || this == AspectRatioPreset.square) {
      return baseRatio;
    }
    
    // Check if this is a naturally portrait format (ratio < 1)
    final isNaturallyPortrait = baseRatio < 1.0;
    
    // If orientation matches natural orientation, use base ratio
    // If orientation is opposite, flip the ratio
    if (isPortrait == isNaturallyPortrait) {
      return baseRatio;
    } else {
      return 1.0 / baseRatio;
    }
  }
  
  // Get label based on orientation
  String getLabel(bool isPortrait) {
    switch (this) {
      case AspectRatioPreset.free:
        return 'Free';
      case AspectRatioPreset.square:
        return 'Square (1:1)';
      case AspectRatioPreset.format67:
        return isPortrait ? '6×7 (6:7)' : '6×7 (7:6)';
      case AspectRatioPreset.format57:
        return isPortrait ? '5×7 (5:7)' : '5×7 (7:5)';
      case AspectRatioPreset.format810:
        return isPortrait ? '8×10 (4:5)' : '8×10 (5:4)';
      case AspectRatioPreset.format645:
        return isPortrait ? '6×4.5 (3:4)' : '6×4.5 (4:3)';
      case AspectRatioPreset.format35mm:
        return isPortrait ? '35mm (2:3)' : '35mm (3:2)';
      case AspectRatioPreset.format169:
        return isPortrait ? 'Story (9:16)' : '16:9';
      case AspectRatioPreset.cinemascope:
        return isPortrait ? 'Cinema (1:2.35)' : 'Cinema (2.35:1)';
      case AspectRatioPreset.xpan:
        return isPortrait ? 'Xpan (24:65)' : 'Xpan (65:24)';
    }
  }
  
  // Base ratio (stored as landscape ratios, all > 1.0 except where naturally portrait)
  double? get ratio {
    switch (this) {
      case AspectRatioPreset.free:
        return null;
      case AspectRatioPreset.square:
        return 1.0;
      case AspectRatioPreset.format67:
        return 6.0 / 7.0;  // Naturally portrait format (taller than wide)
      case AspectRatioPreset.format57:
        return 5.0 / 7.0;  // Naturally portrait format
      case AspectRatioPreset.format810:
        return 4.0 / 5.0;  // Naturally portrait format (8×10 prints)
      case AspectRatioPreset.format645:
        return 4.0 / 3.0;  // Landscape format (medium format 6×4.5)
      case AspectRatioPreset.format35mm:
        return 3.0 / 2.0;  // Landscape format (35mm film)
      case AspectRatioPreset.format169:
        return 16.0 / 9.0; // Landscape format (HD video)
      case AspectRatioPreset.cinemascope:
        return 2.35;       // Landscape format (widescreen cinema)
      case AspectRatioPreset.xpan:
        return 65.0 / 24.0;  // Landscape format (panoramic)
    }
  }
}

/// Manages the crop state
class CropState extends ChangeNotifier {
  bool _isActive = false;
  CropRect _cropRect = CropRect.full();
  CropRect? _savedCropRect; // Store the crop rect when starting to edit
  AspectRatioPreset _aspectRatioPreset = AspectRatioPreset.free;
  bool _showRuleOfThirds = true;
  bool _isPortraitOrientation = false; // Track orientation for all crops
  
  bool get isActive => _isActive;
  CropRect get cropRect => _cropRect;
  AspectRatioPreset get aspectRatioPreset => _aspectRatioPreset;
  bool get showRuleOfThirds => _showRuleOfThirds;
  bool get isPortraitOrientation => _isPortraitOrientation;
  
  void startCropping([CropRect? currentCrop]) {
    _isActive = true;
    // Save the current crop (from pipeline) so we can restore it on cancel
    _savedCropRect = currentCrop ?? CropRect.full();
    // Start with the current crop if there is one
    _cropRect = _savedCropRect!;
    notifyListeners();
  }
  
  void cancelCropping() {
    _isActive = false;
    // Restore the previous crop rect that was saved when we started
    if (_savedCropRect != null) {
      _cropRect = _savedCropRect!;
    }
    notifyListeners();
  }
  
  void applyCrop() {
    _isActive = false;
    notifyListeners();
  }
  
  void updateCropRect(CropRect rect) {
    _cropRect = rect;
    notifyListeners();
  }
  
  // New method that accepts image dimensions to properly calculate orientation
  void updateCropRectWithDimensions(CropRect rect, double imageWidth, double imageHeight) {
    _cropRect = rect;
    
    // For free mode, update orientation based on actual pixel aspect ratio
    if (_aspectRatioPreset == AspectRatioPreset.free) {
      final pixelRect = rect.toPixelRect(imageWidth, imageHeight);
      final pixelWidth = pixelRect.width;
      final pixelHeight = pixelRect.height;
      
      // Check if the crop is portrait (taller than wide) or landscape (wider than tall)
      _isPortraitOrientation = pixelHeight > pixelWidth;
    }
    
    notifyListeners();
  }
  
  void setAspectRatioPreset(AspectRatioPreset preset, double imageWidth, double imageHeight) {
    _aspectRatioPreset = preset;
    // Keep the current orientation when changing presets
    // (don't reset to landscape automatically)
    // Apply the preset with maximum size
    if (preset != AspectRatioPreset.free) {
      _applyPresetWithMaxSize(imageWidth, imageHeight);
    }
    notifyListeners();
  }
  
  void toggleOrientation(double imageWidth, double imageHeight) {
    _isPortraitOrientation = !_isPortraitOrientation;
    
    if (_aspectRatioPreset == AspectRatioPreset.free) {
      // For free mode, rotate the current crop
      _rotateCrop(imageWidth, imageHeight);
    } else {
      // For presets, reapply with the new orientation
      _applyPresetWithMaxSize(imageWidth, imageHeight);
    }
    notifyListeners();
  }
  
  void _rotateCrop(double imageWidth, double imageHeight) {
    // Convert current crop to pixels
    final pixelRect = _cropRect.toPixelRect(imageWidth, imageHeight);
    final currentPixelWidth = pixelRect.width;
    final currentPixelHeight = pixelRect.height;
    
    // Swap width and height
    final newPixelWidth = currentPixelHeight;
    final newPixelHeight = currentPixelWidth;
    
    // Scale down if it doesn't fit
    double scaledWidth = newPixelWidth;
    double scaledHeight = newPixelHeight;
    
    if (scaledWidth > imageWidth) {
      final scale = imageWidth / scaledWidth;
      scaledWidth = imageWidth;
      scaledHeight = scaledHeight * scale;
    }
    
    if (scaledHeight > imageHeight) {
      final scale = imageHeight / scaledHeight;
      scaledHeight = imageHeight;
      scaledWidth = scaledWidth * scale;
    }
    
    // Center the rotated crop
    final centerX = imageWidth / 2;
    final centerY = imageHeight / 2;
    
    final newLeft = (centerX - scaledWidth / 2) / imageWidth;
    final newTop = (centerY - scaledHeight / 2) / imageHeight;
    final newRight = (centerX + scaledWidth / 2) / imageWidth;
    final newBottom = (centerY + scaledHeight / 2) / imageHeight;
    
    _cropRect = CropRect(
      left: newLeft.clamp(0.0, 1.0),
      top: newTop.clamp(0.0, 1.0),
      right: newRight.clamp(0.0, 1.0),
      bottom: newBottom.clamp(0.0, 1.0),
    );
  }
  void toggleRuleOfThirds() {
    _showRuleOfThirds = !_showRuleOfThirds;
    notifyListeners();
  }
  
  void _applyPresetWithMaxSize(double imageWidth, double imageHeight) {
    final targetRatio = _aspectRatioPreset.getRatioWithOrientation(_isPortraitOrientation);
    if (targetRatio == null) return;
    
    final imageRatio = imageWidth / imageHeight;
    double cropWidth, cropHeight;
    
    // Calculate the largest possible crop that fits the image
    if (imageRatio > targetRatio) {
      // Image is wider than target ratio - constrain by height
      cropHeight = imageHeight;
      cropWidth = imageHeight * targetRatio;
    } else {
      // Image is taller than target ratio - constrain by width
      cropWidth = imageWidth;
      cropHeight = imageWidth / targetRatio;
    }
    
    // Convert to normalized coordinates (0-1)
    final normalizedWidth = cropWidth / imageWidth;
    final normalizedHeight = cropHeight / imageHeight;
    
    // Center the crop
    final left = (1.0 - normalizedWidth) / 2;
    final top = (1.0 - normalizedHeight) / 2;
    
    _cropRect = CropRect(
      left: left,
      top: top,
      right: left + normalizedWidth,
      bottom: top + normalizedHeight,
    );
  }
  
  void reset() {
    _cropRect = CropRect.full();
    _savedCropRect = null;
    _aspectRatioPreset = AspectRatioPreset.free;
    _isActive = false;
    notifyListeners();
  }
  
  /// Reset only the editing state when switching images
  /// This preserves the crop rect which will be set from the pipeline/sidecar
  void resetEditingState() {
    _isActive = false;
    _savedCropRect = null;
    // Don't reset _cropRect or _aspectRatioPreset as they may be set from sidecar
    notifyListeners();
  }
}