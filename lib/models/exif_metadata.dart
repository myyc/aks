import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../ffi/raw/libraw_bindings.dart';

/// EXIF metadata extracted from RAW files
class ExifMetadata {
  final String? make;
  final String? model;
  final String? lensMake;
  final String? lensModel;
  final String? software;
  final int? isoSpeed;
  final double? aperture;
  final double? shutterSpeed;
  final double? focalLength;
  final double? focalLength35mm;
  final DateTime? dateTime;
  final int? exposureProgram;
  final int? exposureMode;
  final int? meteringMode;
  final double? exposureCompensation;
  final int? flashMode;
  final int? whiteBalance;

  ExifMetadata({
    this.make,
    this.model,
    this.lensMake,
    this.lensModel,
    this.software,
    this.isoSpeed,
    this.aperture,
    this.shutterSpeed,
    this.focalLength,
    this.focalLength35mm,
    this.dateTime,
    this.exposureProgram,
    this.exposureMode,
    this.meteringMode,
    this.exposureCompensation,
    this.flashMode,
    this.whiteBalance,
  });

  /// Create ExifMetadata from FFI struct
  factory ExifMetadata.fromFfi(Pointer<ExifData> exifPtr) {
    if (exifPtr == nullptr) {
      return ExifMetadata();
    }

    final exif = exifPtr.ref;
    
    // Parse datetime from string format "YYYY:MM:DD HH:MM:SS"
    DateTime? parsedDateTime;
    if (exif.datetime != nullptr) {
      final dateString = exif.datetime.cast<Utf8>().toDartString();
      if (dateString.isNotEmpty) {
        try {
          // Parse format "2025:04:15 14:30:00"
          final parts = dateString.split(' ');
          if (parts.length == 2) {
            final datePart = parts[0]; // "2025:04:15"
            final timePart = parts[1]; // "14:30:00"
            
            final dateComponents = datePart.split(':');
            final timeComponents = timePart.split(':');
            
            if (dateComponents.length == 3 && timeComponents.length == 3) {
              parsedDateTime = DateTime(
                int.parse(dateComponents[0]), // year
                int.parse(dateComponents[1]), // month
                int.parse(dateComponents[2]), // day
                int.parse(timeComponents[0]), // hour
                int.parse(timeComponents[1]), // minute
                int.parse(timeComponents[2]), // second
              );
            }
          }
        } catch (e) {
          // If parsing fails, leave as null
          print('Error parsing date string "$dateString": $e');
        }
      }
    }

    return ExifMetadata(
      make: exif.make != nullptr ? exif.make.cast<Utf8>().toDartString() : null,
      model: exif.model != nullptr ? exif.model.cast<Utf8>().toDartString() : null,
      lensMake: exif.lens_make != nullptr ? exif.lens_make.cast<Utf8>().toDartString() : null,
      lensModel: exif.lens_model != nullptr ? exif.lens_model.cast<Utf8>().toDartString() : null,
      software: exif.software != nullptr ? exif.software.cast<Utf8>().toDartString() : null,
      isoSpeed: exif.iso_speed > 0 ? exif.iso_speed : null,
      aperture: exif.aperture > 0 ? exif.aperture : null,
      shutterSpeed: exif.shutter_speed > 0 ? exif.shutter_speed : null,
      focalLength: exif.focal_length > 0 ? exif.focal_length : null,
      focalLength35mm: exif.focal_length_35mm > 0 ? exif.focal_length_35mm : null,
      dateTime: parsedDateTime,
      exposureProgram: exif.exposure_program >= 0 ? exif.exposure_program : null,
      exposureMode: exif.exposure_mode >= 0 ? exif.exposure_mode : null,
      meteringMode: exif.metering_mode >= 0 ? exif.metering_mode : null,
      exposureCompensation: exif.exposure_compensation != 0 ? exif.exposure_compensation : null,
      flashMode: exif.flash_mode >= 0 ? exif.flash_mode : null,
      whiteBalance: exif.white_balance >= 0 ? exif.white_balance : null,
    );
  }

  /// Get camera name as "Make Model"
  String get cameraName {
    if (make != null && model != null) {
      return '$make $model';
    }
    return make ?? model ?? 'Unknown';
  }

  /// Get lens name as "Make Model"
  String get lensName {
    if (lensMake != null && lensModel != null) {
      return '$lensMake $lensModel';
    }
    return lensMake ?? lensModel ?? 'Unknown';
  }

  /// Get formatted aperture (f/number)
  String get formattedAperture {
    if (aperture == null) return '';
    return 'f/${aperture!.toStringAsFixed(1)}';
  }

  /// Get formatted shutter speed (1/x or x")
  String get formattedShutterSpeed {
    if (shutterSpeed == null) return '';
    
    if (shutterSpeed! >= 1) {
      return '${shutterSpeed!.toStringAsFixed(1)}"';
    } else {
      final reciprocal = (1 / shutterSpeed!).round();
      return '1/$reciprocal';
    }
  }

  /// Get formatted focal length with 35mm equivalent
  String get formattedFocalLength {
    if (focalLength == null) return '';
    
    String result = '${focalLength!.round()}mm';
    if (focalLength35mm != null) {
      result += ' (${focalLength35mm!.round()}mm 35mm equiv.)';
    }
    return result;
  }

  /// Get exposure program name
  String get exposureProgramName {
    switch (exposureProgram) {
      case 0: return 'Not Defined';
      case 1: return 'Manual';
      case 2: return 'Program AE';
      case 3: return 'Aperture-priority AE';
      case 4: return 'Shutter speed priority AE';
      case 5: return 'Creative (Slow speed)';
      case 6: return 'Action (High speed)';
      case 7: return 'Portrait Mode';
      case 8: return 'Landscape Mode';
      default: return 'Unknown';
    }
  }

  /// Get exposure mode name
  String get exposureModeName {
    switch (exposureMode) {
      case 0: return 'Auto';
      case 1: return 'Manual';
      case 2: return 'Auto bracket';
      default: return 'Unknown';
    }
  }

  /// Get metering mode name
  String get meteringModeName {
    switch (meteringMode) {
      case 0: return 'Unknown';
      case 1: return 'Average';
      case 2: return 'Center-weighted average';
      case 3: return 'Spot';
      case 4: return 'Multi-spot';
      case 5: return 'Multi-segment';
      case 6: return 'Partial';
      case 255: return 'Other';
      default: return 'Unknown';
    }
  }

  /// Get formatted date string
  String get formattedDate {
    if (dateTime == null) return '';
    return '${dateTime!.year}-${dateTime!.month.toString().padLeft(2, '0')}-${dateTime!.day.toString().padLeft(2, '0')} ${dateTime!.hour.toString().padLeft(2, '0')}:${dateTime!.minute.toString().padLeft(2, '0')}';
  }

  /// Check if any EXIF data is available
  bool get hasData {
    return make != null || 
           model != null || 
           isoSpeed != null || 
           aperture != null || 
           shutterSpeed != null || 
           focalLength != null ||
           dateTime != null;
  }

  @override
  String toString() {
    return 'ExifMetadata(camera: $cameraName, lens: $lensName, iso: $isoSpeed, aperture: $aperture, shutter: $shutterSpeed, focal: $focalLength)';
  }
}