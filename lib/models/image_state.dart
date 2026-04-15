import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/preferences_service.dart';
import '../services/raw_processor.dart';
import '../services/processing_pipeline.dart';
import '../services/preview_generator.dart';
import '../services/export_service.dart';
import 'edit_pipeline.dart';
import 'highlight_mode.dart';
import 'history_manager.dart';
import 'adjustments.dart';
import 'exif_metadata.dart';
import 'image_cache_bundle.dart';

/// The top-level image state Provider, exposed to the UI via [ChangeNotifier].
///
/// Composes three collaborators:
/// - [EditPipeline]: adjustments + crop + sidecar I/O.
/// - [HistoryManager]: undo/redo snapshots of the pipeline.
/// - [ProcessingPipeline]: raw pixel buffers, processor dispatch, debounce timers.
/// - [ImageCacheBundle]: the four `ui.Image` refs and their disposal.
///
/// This class owns file loading, display-mode flags, and the glue that
/// reacts to [EditPipeline] changes by asking [ProcessingPipeline] to
/// reprocess and piping results into [ImageCacheBundle].
class ImageState extends ChangeNotifier {
  final ImageCacheBundle _cache = ImageCacheBundle();
  final ProcessingPipeline _processing = ProcessingPipeline();
  final EditPipeline _pipeline = EditPipeline();
  final HistoryManager _historyManager = HistoryManager();

  String? _currentFilePath;
  bool _isLoading = false;
  String? _error;
  bool _showOriginal = false;
  bool _hasCrop = false;
  ExifMetadata? _exifData;
  Timer? _historyTimer;
  bool _isUndoRedoOperation = false;
  // Highlight-recovery mode is currently fixed to blend — it matches clip's
  // apparent brightness (via libraw auto-bright) while eliminating the
  // single-channel clip pile-up (e.g. skies). Plumbing supports the other
  // HighlightMode values; when a settings panel lands this can become a
  // user-facing preference again. See CLAUDE.md.
  static const HighlightMode _highlightMode = HighlightMode.blend;

  ImageState() {
    _pipeline.addListener(_onPipelineChanged);
    _historyManager.initialize(_pipeline);
    _processing.onProcessingChanged = notifyListeners;
  }

  // ---- Exposed collaborators (primarily for tests) ----

  ImageCacheBundle get cache => _cache;
  ProcessingPipeline get processing => _processing;

  // ---- Read-only getters for UI consumers ----

  EditPipeline get pipeline => _pipeline;
  HistoryManager get historyManager => _historyManager;

  String? get currentFilePath => _currentFilePath;
  bool get isLoading => _isLoading;
  bool get isProcessing => _processing.isProcessing;
  String? get error => _error;
  bool get hasImage => _cache.hasImage;
  bool get showOriginal => _showOriginal;
  bool get hasCrop => _hasCrop;
  int? get originalWidth => _processing.originalWidth;
  int? get originalHeight => _processing.originalHeight;
  ExifMetadata? get exifData => _exifData;

  ui.Image? get currentImage => _cache.currentImage(showOriginal: _showOriginal);
  ui.Image? get originalImage => _cache.originalImage;

  ui.Image? getDisplayImage(bool isInCropMode) {
    if (isInCropMode && _hasCrop) return originalImage;
    return currentImage;
  }

  int? get actualCurrentWidth {
    final w = _processing.originalWidth;
    if (w == null) return null;
    final c = _pipeline.cropRect;
    if (c == null || (c.left == 0 && c.top == 0 && c.right == 1 && c.bottom == 1)) {
      return w;
    }
    return ((c.right - c.left) * w).round();
  }

  int? get actualCurrentHeight {
    final h = _processing.originalHeight;
    if (h == null) return null;
    final c = _pipeline.cropRect;
    if (c == null || (c.left == 0 && c.top == 0 && c.right == 1 && c.bottom == 1)) {
      return h;
    }
    return ((c.bottom - c.top) * h).round();
  }

  int? get exportImageWidth {
    final img = _cache.full ?? _cache.preview;
    if (img == null) return null;
    final c = _pipeline.cropRect;
    if (c == null) return img.width;
    return ((c.right - c.left) * img.width).round();
  }

  int? get exportImageHeight {
    final img = _cache.full ?? _cache.preview;
    if (img == null) return null;
    final c = _pipeline.cropRect;
    if (c == null) return img.height;
    return ((c.bottom - c.top) * img.height).round();
  }

  // ---- Pipeline change wiring ----

  void _onPipelineChanged() {
    _hasCrop = _cropIsActive(_pipeline.cropRect);

    if (_processing.previewData != null) {
      unawaited(_runPreview());
    }
    if (_processing.originalPreviewData != null) {
      unawaited(_runOriginalImages());
    }

    _processing.scheduleFullResProcessing(
      pipeline: _pipeline,
      onReady: (img) {
        _cache.full = img;
        notifyListeners();
      },
      onError: (_) {},
    );

    _scheduleHistoryEntry();
  }

  Future<void> _runPreview() async {
    try {
      final img = await _processing.processPreview(_pipeline);
      if (img == null) return;
      _cache.preview = img;
      _isLoading = false;
      _error = null;
      notifyListeners();
    } catch (e) {
      setError('Failed to process preview: $e');
    }
  }

  Future<void> _runOriginalImages() async {
    try {
      final adjustmentsOnly = _buildAdjustmentsOnlyPipeline();
      final preview = await _processing.processOriginalPreview(adjustmentsOnly);
      if (preview != null) {
        _cache.originalPreview = preview;
      }
      _processing.scheduleOriginalFullProcessing(
        adjustmentsOnly: adjustmentsOnly,
        onReady: (img) {
          _cache.originalFull = img;
          notifyListeners();
        },
        onError: (_) {},
      );
    } catch (_) {
      // Swallow: original-image processing is best-effort for the crop UI.
    }
  }

  EditPipeline _buildAdjustmentsOnlyPipeline() {
    final p = EditPipeline();
    p.initialize(_currentFilePath ?? '');
    for (final adjustment in _pipeline.adjustments) {
      p.updateAdjustment(adjustment);
    }
    return p;
  }

  void _scheduleHistoryEntry() {
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 500), () {
      if (_isUndoRedoOperation) return;
      final description = _generateChangeDescription();
      if (description.isNotEmpty) {
        _historyManager.addEntry(_pipeline, description);
      }
    });
  }

  String _generateChangeDescription() {
    if (_cropIsActive(_pipeline.cropRect)) {
      return 'Crop applied';
    }
    final names = <String>[];
    for (final adj in _pipeline.adjustments) {
      if (adj is WhiteBalanceAdjustment && (adj.temperature != 5500 || adj.tint != 0)) {
        names.add('White Balance');
      } else if (adj is ExposureAdjustment && adj.value != 0) {
        names.add('Exposure');
      } else if (adj is ContrastAdjustment && adj.value != 0) {
        names.add('Contrast');
      } else if (adj is HighlightsShadowsAdjustment && (adj.highlights != 0 || adj.shadows != 0)) {
        if (adj.highlights != 0) names.add('Highlights');
        if (adj.shadows != 0) names.add('Shadows');
      } else if (adj is BlacksWhitesAdjustment && (adj.blacks != 0 || adj.whites != 0)) {
        if (adj.blacks != 0) names.add('Blacks');
        if (adj.whites != 0) names.add('Whites');
      } else if (adj is SaturationVibranceAdjustment && (adj.saturation != 0 || adj.vibrance != 0)) {
        if (adj.saturation != 0) names.add('Saturation');
        if (adj.vibrance != 0) names.add('Vibrance');
      }
    }
    return names.isEmpty ? '' : 'Adjusted ${names.join(', ')}';
  }

  bool _cropIsActive(dynamic cropRect) {
    if (cropRect == null) return false;
    return cropRect.left != 0 ||
        cropRect.top != 0 ||
        cropRect.right != 1 ||
        cropRect.bottom != 1;
  }

  // ---- Loading ----

  void setLoading(bool loading) {
    _isLoading = loading;
    _error = null;
    notifyListeners();
  }

  void setError(String error) {
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadImage(String filePath) async {
    setLoading(true);
    try {
      final rawResult = await RawProcessor.loadRawFile(
        filePath,
        highlightMode: _highlightMode,
      );
      if (rawResult == null) return;

      _processing.rawData = rawResult.pixelData;
      _processing.originalRawData = rawResult.pixelData;
      _processing.originalWidth = rawResult.pixelData.width;
      _processing.originalHeight = rawResult.pixelData.height;
      _currentFilePath = filePath;
      _exifData = rawResult.exifData;

      final preview = PreviewGenerator.generatePreview(rawResult.pixelData);
      _processing.previewData = preview;
      _processing.originalPreviewData = preview;

      _pipeline.initialize(filePath);
      await _pipeline.loadFromSidecar();
      _hasCrop = _cropIsActive(_pipeline.cropRect);
      _historyManager.initialize(_pipeline);

      await _runOriginalImages();
      await _runPreview();
      _processing.scheduleFullResProcessing(
        pipeline: _pipeline,
        onReady: (img) {
          _cache.full = img;
          notifyListeners();
        },
        onError: (_) {},
      );

      await PreferencesService.saveLastImagePath(filePath);
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> loadLastImage() async {
    final lastPath = await PreferencesService.getLastImagePath();
    if (lastPath != null) {
      await loadImage(lastPath);
    }
  }

  void clear() {
    _processing.clear();
    _cache.clear();
    _currentFilePath = null;
    _isLoading = false;
    _error = null;
    _showOriginal = false;
    _hasCrop = false;
    notifyListeners();
  }

  // ---- Display state ----

  void setZoomLevel(double zoom) {
    final changed = _cache.setUsePreview(PreviewGenerator.shouldUsePreview(zoom));
    if (changed) notifyListeners();
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

  // ---- Pipeline / history ----

  Future<void> savePipelineToSidecar() async {
    if (_currentFilePath != null) {
      await _pipeline.saveToSidecar();
    }
  }

  Future<void> resetAllAdjustments() async {
    _pipeline.resetAll();
    await savePipelineToSidecar();
    _historyManager.addEntry(_pipeline, 'Reset all adjustments');
  }

  void undo() {
    final entry = _historyManager.undo();
    if (entry == null) return;
    _isUndoRedoOperation = true;
    _pipeline.fromJson(entry.pipelineState.toJson());
    _isUndoRedoOperation = false;
  }

  void redo() {
    final entry = _historyManager.redo();
    if (entry == null) return;
    _isUndoRedoOperation = true;
    _pipeline.fromJson(entry.pipelineState.toJson());
    _isUndoRedoOperation = false;
  }

  // ---- Export ----

  Future<bool> exportImage({
    required ExportFormat format,
    int jpegQuality = 90,
    double? resizePercentage,
    String frameType = 'none',
    String frameColor = 'black',
    int borderWidth = 20,
  }) async {
    if (_processing.rawData != null && _cache.full == null) {
      final img = await _processing.processFullResolution(_pipeline);
      if (img != null) _cache.full = img;
    }

    return await ExportService.exportWithFullResolution(
      previewImage: _cache.preview,
      fullImage: _cache.full,
      originalPath: _currentFilePath,
      cropRect: _pipeline.cropRect,
      format: format,
      jpegQuality: jpegQuality,
      resizePercentage: resizePercentage,
      frameType: frameType,
      frameColor: frameColor,
      borderWidth: borderWidth,
    );
  }

  // ---- Lifecycle ----

  @override
  void dispose() {
    _historyTimer?.cancel();
    _pipeline.removeListener(_onPipelineChanged);
    _historyManager.dispose();
    _processing.dispose();
    _cache.dispose();
    super.dispose();
  }
}
