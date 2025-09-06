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

/// Preset aspect ratios for cropping
enum AspectRatioPreset {
  free,
  square,      // 1:1
  portrait43,  // 3:4
  portrait23,  // 2:3
  portrait916, // 9:16 (Instagram Story)
  portrait45,  // 4:5 (Instagram Portrait)
  landscape43, // 4:3
  landscape32, // 3:2
  landscape169,// 16:9
  landscape235,// 2.35:1 (Cinema)
}

extension AspectRatioPresetExtension on AspectRatioPreset {
  String get label {
    switch (this) {
      case AspectRatioPreset.free:
        return 'Free';
      case AspectRatioPreset.square:
        return '1:1';
      case AspectRatioPreset.portrait43:
        return '3:4';
      case AspectRatioPreset.portrait23:
        return '2:3';
      case AspectRatioPreset.portrait916:
        return '9:16';
      case AspectRatioPreset.portrait45:
        return '4:5';
      case AspectRatioPreset.landscape43:
        return '4:3';
      case AspectRatioPreset.landscape32:
        return '3:2';
      case AspectRatioPreset.landscape169:
        return '16:9';
      case AspectRatioPreset.landscape235:
        return '2.35:1';
    }
  }
  
  double? get ratio {
    switch (this) {
      case AspectRatioPreset.free:
        return null;
      case AspectRatioPreset.square:
        return 1.0;
      case AspectRatioPreset.portrait43:
        return 3.0 / 4.0;
      case AspectRatioPreset.portrait23:
        return 2.0 / 3.0;
      case AspectRatioPreset.portrait916:
        return 9.0 / 16.0;
      case AspectRatioPreset.portrait45:
        return 4.0 / 5.0;
      case AspectRatioPreset.landscape43:
        return 4.0 / 3.0;
      case AspectRatioPreset.landscape32:
        return 3.0 / 2.0;
      case AspectRatioPreset.landscape169:
        return 16.0 / 9.0;
      case AspectRatioPreset.landscape235:
        return 2.35;
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
  
  bool get isActive => _isActive;
  CropRect get cropRect => _cropRect;
  AspectRatioPreset get aspectRatioPreset => _aspectRatioPreset;
  bool get showRuleOfThirds => _showRuleOfThirds;
  
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
  
  void setAspectRatioPreset(AspectRatioPreset preset) {
    _aspectRatioPreset = preset;
    // If switching from free to fixed ratio, adjust current crop
    if (preset != AspectRatioPreset.free && preset.ratio != null) {
      _adjustCropToAspectRatio(preset.ratio!);
    }
    notifyListeners();
  }
  
  void toggleRuleOfThirds() {
    _showRuleOfThirds = !_showRuleOfThirds;
    notifyListeners();
  }
  
  void _adjustCropToAspectRatio(double targetRatio) {
    final currentRatio = _cropRect.aspectRatio;
    
    if ((currentRatio - targetRatio).abs() < 0.01) {
      return; // Already close enough
    }
    
    double newLeft = _cropRect.left;
    double newTop = _cropRect.top;
    double newRight = _cropRect.right;
    double newBottom = _cropRect.bottom;
    
    if (currentRatio > targetRatio) {
      // Current is wider, need to make taller
      final targetHeight = _cropRect.width / targetRatio;
      final heightDiff = targetHeight - _cropRect.height;
      newTop -= heightDiff / 2;
      newBottom += heightDiff / 2;
      
      // Clamp to bounds
      if (newTop < 0) {
        newBottom -= newTop;
        newTop = 0;
      }
      if (newBottom > 1) {
        newTop -= (newBottom - 1);
        newBottom = 1;
      }
    } else {
      // Current is taller, need to make wider
      final targetWidth = _cropRect.height * targetRatio;
      final widthDiff = targetWidth - _cropRect.width;
      newLeft -= widthDiff / 2;
      newRight += widthDiff / 2;
      
      // Clamp to bounds
      if (newLeft < 0) {
        newRight -= newLeft;
        newLeft = 0;
      }
      if (newRight > 1) {
        newLeft -= (newRight - 1);
        newRight = 1;
      }
    }
    
    _cropRect = CropRect(
      left: newLeft.clamp(0.0, 1.0),
      top: newTop.clamp(0.0, 1.0),
      right: newRight.clamp(0.0, 1.0),
      bottom: newBottom.clamp(0.0, 1.0),
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