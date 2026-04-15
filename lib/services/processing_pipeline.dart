import 'dart:async';
import 'dart:ui' as ui;

import '../models/edit_pipeline.dart';
import '../models/raw_pixel_data.dart';
import 'processors/processor_factory.dart';

/// Owns the raw pixel buffers and debounce timers that drive image processing.
///
/// Keeps the "edited view" data (possibly pre-cropped by the user), the
/// "original view" data (never cropped, for the crop tool / spacebar toggle),
/// and the two debounce timers that trigger full-resolution processing.
///
/// ImageState is the orchestrator — it feeds data in, asks this class to
/// process, and installs the result into [ImageCacheBundle]. Everything about
/// pixel buffers and timer lifecycles lives here so that ImageState stays
/// a thin façade.
class ProcessingPipeline {
  RawPixelData? rawData;
  RawPixelData? previewData;
  RawPixelData? originalRawData;
  RawPixelData? originalPreviewData;
  int? originalWidth;
  int? originalHeight;

  bool _isProcessingPreview = false;
  bool _isProcessingFull = false;
  Timer? _fullResTimer;
  Timer? _originalFullTimer;
  bool _disposed = false;

  bool get isProcessingPreview => _isProcessingPreview;
  bool get isProcessingFull => _isProcessingFull;
  bool get isProcessing => _isProcessingPreview || _isProcessingFull;

  /// Wiring hook: invoked when the processing flag flips in either direction.
  void Function()? onProcessingChanged;

  static const Duration fullResDebounce = Duration(milliseconds: 1000);
  static const Duration originalFullDebounce = Duration(milliseconds: 500);

  Future<ui.Image?> processPreview(EditPipeline pipeline) async {
    if (previewData == null || _disposed) return null;
    _isProcessingPreview = true;
    onProcessingChanged?.call();
    try {
      final processor = await ProcessorFactory.getProcessor();
      return await processor.processImage(previewData!, pipeline);
    } finally {
      _isProcessingPreview = false;
      onProcessingChanged?.call();
    }
  }

  Future<ui.Image?> processFullResolution(EditPipeline pipeline) async {
    if (rawData == null || _disposed) return null;
    _isProcessingFull = true;
    onProcessingChanged?.call();
    try {
      final processor = await ProcessorFactory.getProcessor();
      return await processor.processImage(rawData!, pipeline);
    } finally {
      _isProcessingFull = false;
      onProcessingChanged?.call();
    }
  }

  Future<ui.Image?> processOriginalPreview(EditPipeline adjustmentsOnly) async {
    if (originalPreviewData == null || _disposed) return null;
    final processor = await ProcessorFactory.getProcessor();
    return await processor.processImage(originalPreviewData!, adjustmentsOnly);
  }

  Future<ui.Image?> processOriginalFull(EditPipeline adjustmentsOnly) async {
    if (originalRawData == null || _disposed) return null;
    final processor = await ProcessorFactory.getProcessor();
    return await processor.processImage(originalRawData!, adjustmentsOnly);
  }

  /// Schedule (or reschedule) full-resolution processing after [fullResDebounce].
  void scheduleFullResProcessing({
    required EditPipeline pipeline,
    required void Function(ui.Image) onReady,
    void Function(Object)? onError,
  }) {
    _fullResTimer?.cancel();
    _fullResTimer = Timer(fullResDebounce, () async {
      if (_disposed) return;
      try {
        final img = await processFullResolution(pipeline);
        if (_disposed || img == null) {
          img?.dispose();
          return;
        }
        onReady(img);
      } catch (e) {
        onError?.call(e);
      }
    });
  }

  /// Schedule (or reschedule) original-full-resolution processing after
  /// [originalFullDebounce]. Fixes the previous unawaited-timer leak: the
  /// handle is stored and cancelled in [cancelTimers] / [dispose].
  void scheduleOriginalFullProcessing({
    required EditPipeline adjustmentsOnly,
    required void Function(ui.Image) onReady,
    void Function(Object)? onError,
  }) {
    _originalFullTimer?.cancel();
    _originalFullTimer = Timer(originalFullDebounce, () async {
      if (_disposed) return;
      try {
        final img = await processOriginalFull(adjustmentsOnly);
        if (_disposed || img == null) {
          img?.dispose();
          return;
        }
        onReady(img);
      } catch (e) {
        onError?.call(e);
      }
    });
  }

  void cancelTimers() {
    _fullResTimer?.cancel();
    _fullResTimer = null;
    _originalFullTimer?.cancel();
    _originalFullTimer = null;
  }

  /// Forget all pixel buffers and cancel in-flight timers.
  /// Safe to call repeatedly.
  void clear() {
    cancelTimers();
    rawData = null;
    previewData = null;
    originalRawData = null;
    originalPreviewData = null;
    originalWidth = null;
    originalHeight = null;
    _isProcessingPreview = false;
    _isProcessingFull = false;
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
