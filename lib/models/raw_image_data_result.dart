import 'package:aks/models/exif_metadata.dart';
import 'package:aks/services/image_processor.dart' as img_proc;

/// Result class containing both RAW pixel data and EXIF metadata
class RawImageDataResult {
  final img_proc.RawPixelData pixelData;
  final ExifMetadata? exifData;

  RawImageDataResult({
    required this.pixelData,
    this.exifData,
  });
}