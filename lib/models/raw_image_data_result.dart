import 'package:aks/models/exif_metadata.dart';
import 'package:aks/models/raw_pixel_data.dart';

/// Result class containing both RAW pixel data and EXIF metadata
class RawImageDataResult {
  final RawPixelData pixelData;
  final ExifMetadata? exifData;

  RawImageDataResult({
    required this.pixelData,
    this.exifData,
  });
}