import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/preferences_service.dart';
import '../services/raw_processor.dart';
import '../services/image_processor.dart';
import '../services/processors/processor_factory.dart';
import '../services/processors/image_processor_interface.dart';
import '../services/preview_generator.dart';
import '../services/export_service.dart';
import 'edit_pipeline.dart';
import 'history_manager.dart';
import 'adjustments.dart';

class ImageState extends ChangeNotifier {
  ui.Image? _currentImage;
  ui.Image? _previewImage;
  ui.Image? _fullImage;
  ui.Image? _originalPreviewImage;
  ui.Image? _originalFullImage;
  RawPixelData? _rawData;
  RawPixelData? _previewData;
  String? _currentFilePath;
  bool _isLoading = false;
  bool _isProcessing = false;
  bool _isProcessingFull = false;
  String? _error;
  bool _showOriginal = false;
  final EditPipeline _pipeline = EditPipeline();
  Timer? _fullResTimer;
  bool _usePreview = true;
  final HistoryManager _historyManager = HistoryManager();

  ui.Image? get currentImage {
    if (_showOriginal) {
      return _usePreview ? (_originalPreviewImage ?? _originalFullImage) : (_originalFullImage ?? _originalPreviewImage);
    }
    return _usePreview ? (_previewImage ?? _fullImage) : (_fullImage ?? _previewImage);
  }
  String? get currentFilePath => _currentFilePath;
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing || _isProcessingFull;
  String? get error => _error;
  bool get hasImage => _currentImage != null || _previewImage != null || _fullImage != null;
  EditPipeline get pipeline => _pipeline;
  HistoryManager get historyManager => _historyManager;
  bool get showOriginal => _showOriginal;
  
  // Get dimensions of the image that will be exported (accounting for crop)
  int? get exportImageWidth {
    final img = _fullImage ?? _previewImage;
    if (img == null) return null;
    if (_pipeline.cropRect == null) return img.width;
    
    // Calculate cropped dimensions
    final cropWidth = (_pipeline.cropRect!.right - _pipeline.cropRect!.left) * img.width;
    return cropWidth.round();
  }
  
  int? get exportImageHeight {
    final img = _fullImage ?? _previewImage;
    if (img == null) return null;
    if (_pipeline.cropRect == null) return img.height;
    
    // Calculate cropped dimensions
    final cropHeight = (_pipeline.cropRect!.bottom - _pipeline.cropRect!.top) * img.height;
    return cropHeight.round();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    _error = null;
    notifyListeners();
  }

  ImageState() {
    // Listen to pipeline changes
    _pipeline.addListener(_onPipelineChanged);
    // Initialize processor factory (will create appropriate processor)
    ProcessorFactory.getProcessor();
    // Initialize history with empty state
    _historyManager.initialize(_pipeline);
  }
  
  Timer? _historyTimer;
  
  void _onPipelineChanged() {
    print('ImageState: Pipeline changed, cropRect=${_pipeline.cropRect}');
    // Reprocess preview immediately when pipeline changes
    if (_previewData != null) {
      print('ImageState: Triggering preview reprocess');
      _processPreview();
    }
    // Schedule full resolution processing
    _scheduleFullResProcessing();
    
    // Schedule history entry (debounced to avoid too many entries during slider dragging)
    _scheduleHistoryEntry();
  }
  
  void _scheduleHistoryEntry() {
    // Cancel previous timer
    _historyTimer?.cancel();
    
    // Schedule new history entry after delay
    _historyTimer = Timer(const Duration(milliseconds: 500), () {
      // Don't add history during undo/redo operations
      if (_isUndoRedoOperation) return;
      
      // Generate description based on what changed
      String description = _generateChangeDescription();
      
      // Add to history (duplicate check is done in history manager)
      if (description.isNotEmpty) {
        _historyManager.addEntry(_pipeline, description);
      }
    });
  }
  
  String _generateChangeDescription() {
    // Check for crop changes
    if (_pipeline.cropRect != null) {
      final crop = _pipeline.cropRect!;
      if (crop.left != 0 || crop.top != 0 || crop.right != 1 || crop.bottom != 1) {
        return 'Crop applied';
      }
    }
    
    // Check for adjustment changes
    final adjustments = <String>[];
    
    for (final adj in _pipeline.adjustments) {
      if (adj is WhiteBalanceAdjustment && (adj.temperature != 5500 || adj.tint != 0)) {
        adjustments.add('White Balance');
      } else if (adj is ExposureAdjustment && adj.value != 0) {
        adjustments.add('Exposure');
      } else if (adj is ContrastAdjustment && adj.value != 0) {
        adjustments.add('Contrast');
      } else if (adj is HighlightsShadowsAdjustment && (adj.highlights != 0 || adj.shadows != 0)) {
        if (adj.highlights != 0) adjustments.add('Highlights');
        if (adj.shadows != 0) adjustments.add('Shadows');
      } else if (adj is BlacksWhitesAdjustment && (adj.blacks != 0 || adj.whites != 0)) {
        if (adj.blacks != 0) adjustments.add('Blacks');
        if (adj.whites != 0) adjustments.add('Whites');
      } else if (adj is SaturationVibranceAdjustment && (adj.saturation != 0 || adj.vibrance != 0)) {
        if (adj.saturation != 0) adjustments.add('Saturation');
        if (adj.vibrance != 0) adjustments.add('Vibrance');
      }
    }
    
    if (adjustments.isNotEmpty) {
      return 'Adjusted ${adjustments.join(', ')}';
    }
    
    return '';
  }
  
  bool _isUndoRedoOperation = false;
  
  Future<void> loadImage(String filePath) async {
    setLoading(true);
    try {
      // Load raw data
      final rawData = await RawProcessor.loadRawFile(filePath);
      if (rawData != null) {
        _rawData = rawData;
        _currentFilePath = filePath;
        
        // Generate preview data
        _previewData = PreviewGenerator.generatePreview(rawData);
        
        // Initialize pipeline for this image
        _pipeline.initialize(filePath);
        
        // Try to load sidecar adjustments if they exist
        await _pipeline.loadFromSidecar();
        
        // Initialize history with loaded state
        _historyManager.initialize(_pipeline);
        
        // Process original images first (without adjustments)
        await _processOriginalImages();
        
        // Process preview immediately
        await _processPreview();
        
        // Schedule full resolution processing
        _scheduleFullResProcessing();
        
        // Save the last opened image path
        PreferencesService.saveLastImagePath(filePath);
      }
    } catch (e) {
      setError(e.toString());
    }
  }
  
  Future<void> _processPreview() async {
    if (_previewData == null) return;
    
    _isProcessing = true;
    notifyListeners();
    
    try {
      // Process the preview data with current adjustments using isolate
      final processor = await ProcessorFactory.getProcessor();
      final processedImage = await processor.processImage(
        _previewData!,
        _pipeline,
      );
      
      // Dispose old preview image
      _previewImage?.dispose();
      
      // Set new preview image
      _previewImage = processedImage;
      _isProcessing = false;
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      print('Error processing preview: $e');
      setError('Failed to process preview: $e');
    }
  }
  
  Future<void> _processFullResolution() async {
    if (_rawData == null) return;
    
    _isProcessingFull = true;
    notifyListeners();
    
    try {
      // Process the full resolution data with current adjustments
      final processor = await ProcessorFactory.getProcessor();
      final processedImage = await processor.processImage(
        _rawData!,
        _pipeline,
      );
      
      // Dispose old full image
      _fullImage?.dispose();
      
      // Set new full image
      _fullImage = processedImage;
      _isProcessingFull = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      print('Error processing full resolution: $e');
      // Don't show error for full res processing failures
      _isProcessingFull = false;
      notifyListeners();
    }
  }
  
  void _scheduleFullResProcessing() {
    // Cancel previous timer
    _fullResTimer?.cancel();
    
    // Schedule new full resolution processing after delay
    _fullResTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_rawData != null) {
        _processFullResolution();
      }
    });
  }
  
  void setZoomLevel(double zoom) {
    // Switch between preview and full resolution based on zoom
    final shouldUsePreview = PreviewGenerator.shouldUsePreview(zoom);
    if (shouldUsePreview != _usePreview) {
      _usePreview = shouldUsePreview;
      notifyListeners();
    }
  }
  
  void setShowOriginal(bool show) {
    if (_showOriginal != show) {
      _showOriginal = show;
      notifyListeners();
    }
  }
  
  void toggleOriginal() {
    _showOriginal = !_showOriginal;
    notifyListeners();
  }
  
  Future<void> _processOriginalImages() async {
    if (_previewData == null) return;
    
    try {
      // Create an empty pipeline (no adjustments) for original
      final emptyPipeline = EditPipeline();
      emptyPipeline.initialize(_currentFilePath ?? '');
      
      // Process preview without adjustments
      final processor = await ProcessorFactory.getProcessor();
      final originalPreview = await processor.processImage(
        _previewData!,
        emptyPipeline,
      );
      
      // Dispose old original preview
      _originalPreviewImage?.dispose();
      _originalPreviewImage = originalPreview;
      
      // Also process full resolution original in background
      if (_rawData != null) {
        Timer(const Duration(milliseconds: 500), () async {
          final processor = await ProcessorFactory.getProcessor();
          final originalFull = await processor.processImage(
            _rawData!,
            emptyPipeline,
          );
          _originalFullImage?.dispose();
          _originalFullImage = originalFull;
        });
      }
    } catch (e) {
      print('Error processing original images: $e');
      // Don't fail if original processing fails
    }
  }

  void setError(String error) {
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  void clear() {
    _fullResTimer?.cancel();
    _currentImage?.dispose();
    _previewImage?.dispose();
    _fullImage?.dispose();
    _originalPreviewImage?.dispose();
    _originalFullImage?.dispose();
    _currentImage = null;
    _previewImage = null;
    _fullImage = null;
    _originalPreviewImage = null;
    _originalFullImage = null;
    _rawData = null;
    _previewData = null;
    _currentFilePath = null;
    _isLoading = false;
    _isProcessing = false;
    _isProcessingFull = false;
    _error = null;
    _showOriginal = false;
    notifyListeners();
  }

  Future<void> loadLastImage() async {
    final lastPath = await PreferencesService.getLastImagePath();
    if (lastPath != null) {
      await loadImage(lastPath);
    }
  }
  
  Future<void> savePipelineToSidecar() async {
    if (_currentFilePath != null) {
      await _pipeline.saveToSidecar();
    }
  }
  
  Future<void> resetAllAdjustments() async {
    _pipeline.resetAll();
    // Save the reset state to sidecar (clears the sidecar if no adjustments remain)
    await savePipelineToSidecar();
    // Add to history
    _historyManager.addEntry(_pipeline, "Reset all adjustments");
  }
  
  void undo() {
    final entry = _historyManager.undo();
    if (entry != null) {
      _isUndoRedoOperation = true;
      // Apply the previous state
      _pipeline.fromJson(entry.pipelineState.toJson());
      _isUndoRedoOperation = false;
    }
  }
  
  void redo() {
    final entry = _historyManager.redo();
    if (entry != null) {
      _isUndoRedoOperation = true;
      // Apply the next state
      _pipeline.fromJson(entry.pipelineState.toJson());
      _isUndoRedoOperation = false;
    }
  }
  
  Future<bool> exportImage({
    required ExportFormat format,
    int jpegQuality = 90,
    double? resizePercentage,
    String frameType = 'none',
    String frameColor = 'black',
    int borderWidth = 20,
  }) async {
    // Make sure full resolution is processed before export
    if (_rawData != null && _fullImage == null) {
      await _processFullResolution();
    }
    
    // Log export dimensions to verify crop is applied
    final exportImg = _fullImage ?? _previewImage;
    if (exportImg != null) {
      print('Exporting image with dimensions: ${exportImg.width}x${exportImg.height}');
      if (_pipeline.cropRect != null) {
        print('Crop is applied: ${_pipeline.cropRect}');
      }
    }
    
    return await ExportService.exportWithFullResolution(
      previewImage: _previewImage,
      fullImage: _fullImage,
      originalPath: _currentFilePath,
      cropRect: _pipeline.cropRect,  // Pass the crop rect for export
      format: format,
      jpegQuality: jpegQuality,
      resizePercentage: resizePercentage,
      frameType: frameType,
      frameColor: frameColor,
      borderWidth: borderWidth,
    );
  }

  @override
  void dispose() {
    _fullResTimer?.cancel();
    _historyTimer?.cancel();
    _pipeline.removeListener(_onPipelineChanged);
    _historyManager.dispose();
    _currentImage?.dispose();
    _previewImage?.dispose();
    _fullImage?.dispose();
    _originalPreviewImage?.dispose();
    _originalFullImage?.dispose();
    ProcessorFactory.dispose();
    super.dispose();
  }
}