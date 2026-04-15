import 'dart:ui' as ui;
import '../models/crop_state.dart';

/// Crop a fully-rendered Flutter image to the given normalized rect.
///
/// Used by the export pipeline. Pixel-buffer crops happen separately in
/// [BaseImageProcessor.applyCrop] (see lib/services/processors/image_processor_interface.dart),
/// which operates on raw pixel data before processing.
Future<ui.Image> applyCropToImage(ui.Image source, CropRect cropRect) async {
  final width = source.width;
  final height = source.height;

  final cropLeft = (width * cropRect.left).round();
  final cropTop = (height * cropRect.top).round();
  final cropRight = (width * cropRect.right).round();
  final cropBottom = (height * cropRect.bottom).round();
  final cropWidth = cropRight - cropLeft;
  final cropHeight = cropBottom - cropTop;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

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

  final picture = recorder.endRecording();
  return await picture.toImage(cropWidth, cropHeight);
}
