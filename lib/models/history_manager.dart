import 'package:flutter/foundation.dart';
import 'edit_pipeline.dart';
import 'crop_state.dart';

class HistoryEntry {
  final EditPipeline pipelineState;
  final CropRect? cropRect;
  final String description;
  final DateTime timestamp;

  HistoryEntry({
    required this.pipelineState,
    required this.cropRect,
    required this.description,
    required this.timestamp,
  });
}

class HistoryManager extends ChangeNotifier {
  final List<HistoryEntry> _history = [];
  int _currentIndex = -1;
  static const int maxHistorySize = 50;
  
  bool get canUndo => _currentIndex > 0;
  bool get canRedo => _currentIndex < _history.length - 1;
  
  String? get lastActionDescription => _currentIndex >= 0 && _currentIndex < _history.length
      ? _history[_currentIndex].description
      : null;
  
  /// Add a new state to history
  void addEntry(EditPipeline pipeline, String description) {
    // Create a snapshot of the current pipeline state
    final pipelineSnapshot = EditPipeline();
    pipelineSnapshot.fromJson(pipeline.toJson());
    
    // Check if this state is identical to the current state in history
    if (_currentIndex >= 0 && _currentIndex < _history.length) {
      final currentState = _history[_currentIndex].pipelineState;
      if (_areStatesEqual(currentState, pipelineSnapshot)) {
        // State hasn't changed, don't add to history
        return;
      }
    }
    
    // Remove any entries after current index (for when we undo then make a new change)
    if (_currentIndex < _history.length - 1) {
      _history.removeRange(_currentIndex + 1, _history.length);
    }
    
    // Add new entry
    _history.add(HistoryEntry(
      pipelineState: pipelineSnapshot,
      cropRect: pipeline.cropRect,
      description: description,
      timestamp: DateTime.now(),
    ));
    
    // Limit history size
    if (_history.length > maxHistorySize) {
      _history.removeAt(0);
      if (_currentIndex > 0) _currentIndex--;
    } else {
      _currentIndex++;
    }
    
    notifyListeners();
  }
  
  /// Check if two pipeline states are equal
  bool _areStatesEqual(EditPipeline state1, EditPipeline state2) {
    final json1 = state1.toJson();
    final json2 = state2.toJson();
    
    // Compare crop rects
    final crop1 = json1['crop_rect'];
    final crop2 = json2['crop_rect'];
    if (crop1 == null && crop2 == null) {
      // Both null, equal
    } else if (crop1 == null || crop2 == null) {
      return false; // One null, not equal
    } else {
      // Compare crop values
      if (crop1['left'] != crop2['left'] ||
          crop1['top'] != crop2['top'] ||
          crop1['right'] != crop2['right'] ||
          crop1['bottom'] != crop2['bottom']) {
        return false;
      }
    }
    
    // Compare adjustments
    final adj1 = json1['adjustments'] as List;
    final adj2 = json2['adjustments'] as List;
    
    if (adj1.length != adj2.length) return false;
    
    for (int i = 0; i < adj1.length; i++) {
      final a1 = adj1[i] as Map<String, dynamic>;
      final a2 = adj2[i] as Map<String, dynamic>;
      
      // Find matching adjustment by type
      final matchingAdj = adj2.firstWhere(
        (a) => a['type'] == a1['type'],
        orElse: () => <String, dynamic>{},
      );
      
      if (matchingAdj.isEmpty) return false;
      
      // Compare all values in the adjustment
      for (final key in a1.keys) {
        if (a1[key] != matchingAdj[key]) {
          return false;
        }
      }
    }
    
    return true;
  }
  
  /// Get the state for undo
  HistoryEntry? undo() {
    if (!canUndo) return null;
    
    _currentIndex--;
    notifyListeners();
    return _history[_currentIndex];
  }
  
  /// Get the state for redo
  HistoryEntry? redo() {
    if (!canRedo) return null;
    
    _currentIndex++;
    notifyListeners();
    return _history[_currentIndex];
  }
  
  /// Clear all history
  void clear() {
    _history.clear();
    _currentIndex = -1;
    notifyListeners();
  }
  
  /// Initialize with a base state
  void initialize(EditPipeline pipeline) {
    clear();
    addEntry(pipeline, "Initial state");
  }
}