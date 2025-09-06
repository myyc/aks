import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'adjustments.dart';
import 'crop_state.dart';

/// Manages the edit pipeline for non-destructive image editing
class EditPipeline extends ChangeNotifier {
  String? _sourceFile;
  final List<Adjustment> _adjustments = [];
  CropRect? _cropRect;
  
  String? get sourceFile => _sourceFile;
  List<Adjustment> get adjustments => List.unmodifiable(_adjustments);
  CropRect? get cropRect => _cropRect;
  
  /// Check if any adjustments have been made
  bool get hasAdjustments {
    // Check if crop is applied
    if (_cropRect != null && 
        (_cropRect!.left != 0 || _cropRect!.top != 0 || 
         _cropRect!.right != 1 || _cropRect!.bottom != 1)) {
      return true;
    }
    
    // Check other adjustments
    return _adjustments.any((adj) {
      if (adj is WhiteBalanceAdjustment) {
        return adj.temperature != 5500.0 || adj.tint != 0;
      } else if (adj is ExposureAdjustment) {
        return adj.value != 0;
      } else if (adj is ContrastAdjustment) {
        return adj.value != 0;
      } else if (adj is HighlightsShadowsAdjustment) {
        return adj.highlights != 0 || adj.shadows != 0;
      } else if (adj is BlacksWhitesAdjustment) {
        return adj.blacks != 0 || adj.whites != 0;
      } else if (adj is SaturationVibranceAdjustment) {
        return adj.saturation != 0 || adj.vibrance != 0;
      } else if (adj is ToneCurveAdjustment) {
        return !adj.isDefault;
      }
      return false;
    });
  }
  
  /// Set the crop rectangle
  void setCropRect(CropRect? rect) {
    _cropRect = rect;
    notifyListeners();
  }
  
  /// Initialize pipeline for a new image
  void initialize(String sourceFile) {
    _sourceFile = sourceFile;
    _adjustments.clear();
    
    // Add default adjustments (all at neutral values)
    _adjustments.addAll([
      WhiteBalanceAdjustment(),
      ExposureAdjustment(),
      ContrastAdjustment(),
      HighlightsShadowsAdjustment(),
      BlacksWhitesAdjustment(),
      SaturationVibranceAdjustment(),
      ToneCurveAdjustment(),
    ]);
    
    notifyListeners();
  }
  
  /// Update a specific adjustment
  void updateAdjustment(Adjustment adjustment) {
    final index = _adjustments.indexWhere((a) => a.type == adjustment.type);
    if (index != -1) {
      _adjustments[index] = adjustment;
      notifyListeners();
    }
  }
  
  /// Get adjustment by type
  T? getAdjustment<T extends Adjustment>(String type) {
    try {
      return _adjustments.firstWhere((a) => a.type == type) as T;
    } catch (e) {
      return null;
    }
  }
  
  /// Reset all adjustments to default values
  void resetAll() {
    for (int i = 0; i < _adjustments.length; i++) {
      _adjustments[i] = _adjustments[i].reset();
    }
    _cropRect = null; // Reset crop as well
    notifyListeners();
  }
  
  /// Reset a specific adjustment
  void resetAdjustment(String type) {
    final index = _adjustments.indexWhere((a) => a.type == type);
    if (index != -1) {
      _adjustments[index] = _adjustments[index].reset();
      notifyListeners();
    }
  }
  
  /// Convert pipeline to JSON
  Map<String, dynamic> toJson() {
    return {
      'version': '1.0',
      'source_file': _sourceFile,
      'adjustments': _adjustments.map((a) => a.toJson()).toList(),
      'crop_rect': _cropRect?.toJson(),
    };
  }
  
  /// Load pipeline from JSON
  void fromJson(Map<String, dynamic> json) {
    _sourceFile = json['source_file'];
    
    // Start with default adjustments
    _adjustments.clear();
    _adjustments.addAll([
      WhiteBalanceAdjustment(),
      ExposureAdjustment(),
      ContrastAdjustment(),
      HighlightsShadowsAdjustment(),
      BlacksWhitesAdjustment(),
      SaturationVibranceAdjustment(),
      ToneCurveAdjustment(),
    ]);
    
    // Override with values from JSON if present
    if (json['adjustments'] != null) {
      for (var adjJson in json['adjustments']) {
        final adjustment = Adjustment.fromJson(adjJson);
        final index = _adjustments.indexWhere((a) => a.type == adjustment.type);
        if (index != -1) {
          _adjustments[index] = adjustment;
        } else {
          // If it's a new adjustment type not in defaults, add it
          _adjustments.add(adjustment);
        }
      }
    }
    
    // Load crop rect if present
    if (json['crop_rect'] != null) {
      _cropRect = CropRect.fromJson(json['crop_rect']);
    } else {
      _cropRect = null;
    }
    
    notifyListeners();
  }
  
  /// Save pipeline to a JSON file
  Future<void> saveToFile(String filePath) async {
    final file = File(filePath);
    final jsonString = jsonEncode(toJson());
    await file.writeAsString(jsonString);
  }
  
  /// Load pipeline from a JSON file
  Future<void> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString);
      fromJson(json);
    }
  }
  
  /// Get sidecar file path for the current image
  String? getSidecarPath() {
    if (_sourceFile == null) return null;
    return '$_sourceFile.aks.json';
  }
  
  /// Save to sidecar file
  Future<void> saveToSidecar() async {
    final sidecarPath = getSidecarPath();
    if (sidecarPath != null) {
      final file = File(sidecarPath);
      
      // If there are no adjustments and no crop, delete the sidecar file
      if (!hasAdjustments) {
        if (await file.exists()) {
          await file.delete();
          print('Deleted sidecar file: $sidecarPath');
        }
      } else {
        // Save the adjustments
        await saveToFile(sidecarPath);
        print('Saved sidecar file: $sidecarPath');
      }
    }
  }
  
  /// Load from sidecar file if it exists
  Future<bool> loadFromSidecar() async {
    final sidecarPath = getSidecarPath();
    if (sidecarPath != null) {
      final file = File(sidecarPath);
      if (await file.exists()) {
        await loadFromFile(sidecarPath);
        return true;
      }
    }
    return false;
  }
  
  /// Clear the pipeline
  void clear() {
    _sourceFile = null;
    _adjustments.clear();
    _cropRect = null;
    notifyListeners();
  }
}