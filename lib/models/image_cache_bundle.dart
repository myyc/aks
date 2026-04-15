import 'dart:ui' as ui;

/// Holds the four `ui.Image` references backing the viewer (preview + full,
/// times edited + original-no-crop) plus the preview/full selector.
///
/// Each setter disposes the previous reference automatically, centralising
/// the disposal that was previously scattered across [ImageState].
class ImageCacheBundle {
  ui.Image? _preview;
  ui.Image? _full;
  ui.Image? _originalPreview;
  ui.Image? _originalFull;
  bool _usePreview = true;

  ui.Image? get preview => _preview;
  ui.Image? get full => _full;
  ui.Image? get originalPreview => _originalPreview;
  ui.Image? get originalFull => _originalFull;
  bool get usePreview => _usePreview;

  bool get hasImage => _preview != null || _full != null;

  set preview(ui.Image? img) {
    if (identical(_preview, img)) return;
    _preview?.dispose();
    _preview = img;
  }

  set full(ui.Image? img) {
    if (identical(_full, img)) return;
    _full?.dispose();
    _full = img;
  }

  set originalPreview(ui.Image? img) {
    if (identical(_originalPreview, img)) return;
    _originalPreview?.dispose();
    _originalPreview = img;
  }

  set originalFull(ui.Image? img) {
    if (identical(_originalFull, img)) return;
    _originalFull?.dispose();
    _originalFull = img;
  }

  /// Returns true if the value actually changed.
  bool setUsePreview(bool value) {
    if (_usePreview == value) return false;
    _usePreview = value;
    return true;
  }

  /// The image to display in the viewer.
  ///
  /// When [showOriginal] is true (spacebar toggle), returns the original-no-crop
  /// version. Falls back to the other resolution if the preferred one is null.
  ui.Image? currentImage({required bool showOriginal}) {
    if (showOriginal) {
      return _usePreview
          ? (_originalPreview ?? _originalFull)
          : (_originalFull ?? _originalPreview);
    }
    return _usePreview ? (_preview ?? _full) : (_full ?? _preview);
  }

  /// The original-no-crop image for the current resolution tier.
  ui.Image? get originalImage => _usePreview
      ? (_originalPreview ?? _originalFull)
      : (_originalFull ?? _originalPreview);

  /// Dispose and null out all four image refs.
  void clear() {
    preview = null;
    full = null;
    originalPreview = null;
    originalFull = null;
  }

  /// Alias for [clear]; safe to call twice.
  void dispose() => clear();
}
