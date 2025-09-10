import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import '../common/ffi_base.dart';
import '../common/platform_utils.dart';
import 'jpeg_bindings.dart';

/// High-level JPEG processor with FFI integration
class JpegProcessor extends FfiBase {
  static DynamicLibrary? _library;
  static JpegBindings? _bindings;
  
  /// Initialize the JPEG processor
  static void initialize() {
    if (_bindings != null) return;
    
    _library = FfiBase.loadLibrary(
      'jpeg_binding',
      linuxPaths: [
        ...PlatformUtils.commonLibraryPaths,
        '${Directory.current.path}/build/linux/x64/debug/bundle/lib',
      ],
      macosPaths: PlatformUtils.commonLibraryPaths,
      windowsPaths: PlatformUtils.commonLibraryPaths,
    );
    
    _bindings = JpegBindings(_library!);
  }
  
  /// Compress image to JPEG with specified quality
  static Future<Uint8List> compressImage({
    required ui.Image image,
    int quality = 90,
  }) async {
    initialize();
    
    // Get image data as RGBA
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    
    if (byteData == null) {
      throw Exception('Failed to convert image to byte data');
    }
    
    final rgbaData = byteData.buffer.asUint8List();
    
    // Initialize JPEG compression
    final handle = _bindings!.jpegCompressInit(
      image.width,
      image.height,
      quality,
    );
    
    if (handle == nullptr) {
      throw Exception('Failed to initialize JPEG compression');
    }
    
    try {
      // Get pointer to RGBA data
      final rgbaPointer = FfiBase.mallocAndCopy(rgbaData);
      
      try {
        // Compress to JPEG
        final jpegBuffer = _bindings!.jpegCompressRgba(
          handle,
          rgbaPointer,
        );
        
        if (jpegBuffer.data == nullptr) {
          throw Exception('Failed to compress JPEG');
        }
        
        try {
          // Convert to Dart Uint8List
          final jpegData = Uint8List(jpegBuffer.size);
          for (int i = 0; i < jpegBuffer.size; i++) {
            jpegData[i] = jpegBuffer.data[i];
          }
          
          return jpegData;
        } finally {
          _bindings!.jpegFreeBuffer(jpegBuffer);
        }
      } finally {
        malloc.free(rgbaPointer);
      }
    } finally {
      _bindings!.jpegCompressCleanup(handle);
    }
  }
  
  /// Get the JPEG bindings instance
  static JpegBindings get bindings {
    if (_bindings == null) {
      initialize();
    }
    return _bindings!;
  }
}