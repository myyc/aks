import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import '../common/ffi_base.dart';
import '../common/platform_utils.dart';
import 'libraw_bindings.dart';
import '../../models/raw_pixel_data.dart';
import '../../services/image_processor.dart';

/// High-level RAW processor that implements ImageProcessorInterface
class RawProcessor extends FfiBase implements ImageProcessorInterface {
  static DynamicLibrary? _library;
  static LibRawBindings? _bindings;
  
  /// Initialize the RAW processor
  static void initialize() {
    if (_bindings != null) return;
    
    _library = loadLibrary(
      'raw_processor',
      linuxPaths: [
        ...PlatformUtils.commonLibraryPaths,
        '${Directory.current.path}/build/linux/x64/debug/bundle/lib',
      ],
      macosPaths: [
        ...PlatformUtils.commonLibraryPaths,
        '/opt/homebrew/lib',
        '/usr/local/opt/libraw/lib',
      ],
      windowsPaths: PlatformUtils.commonLibraryPaths,
    );
    
    _bindings = LibRawBindings(_library!);
  }
  
  @override
  Future<RawPixelData> processFile(String path) async {
    initialize();
    
    // Initialize processor
    final processor = _bindings!.raw_processor_init();
    if (processor == nullptr) {
      throw Exception('Failed to initialize RAW processor: ${_getLastError()}');
    }
    
    try {
      // Open file
      final pathPtr = toCString(path);
      final openResult = _bindings!.raw_processor_open(processor, pathPtr);
      malloc.free(pathPtr);
      
      if (openResult != 0) {
        throw Exception('Failed to open RAW file: ${_getLastError()}');
      }
      
      // Process RAW data
      final processResult = _bindings!.raw_processor_process(processor);
      if (processResult != 0) {
        throw Exception('Failed to process RAW: ${_getLastError()}');
      }
      
      // Get RGB data
      final imageData = _bindings!.raw_processor_get_rgb(processor);
      if (imageData == nullptr) {
        throw Exception('Failed to get RGB data: ${_getLastError()}');
      }
      
      try {
        // Extract data
        final width = imageData.ref.info.width;
        final height = imageData.ref.info.height;
        final size = imageData.ref.size;
        final dataPtr = imageData.ref.data;
        
        // Copy pixel data
        final pixelData = Uint8List(size);
        for (int i = 0; i < size; i++) {
          pixelData[i] = dataPtr[i];
        }
        
        return RawPixelData(
          pixels: pixelData,
          width: width,
          height: height,
          bitsPerSample: imageData.ref.info.bits,
          samplesPerPixel: imageData.ref.info.colors,
        );
      } finally {
        _bindings!.raw_processor_free_image(imageData);
      }
    } finally {
      _bindings!.raw_processor_cleanup(processor);
    }
  }
  
  @override
  bool supportsFormat(String format) {
    final lowerFormat = format.toLowerCase();
    return [
      'cr2', 'nef', 'arw', 'orf', 'rw2', 'pef', 'dng',
      'cr3', 'crw', 'mrw', 'raf', 'x3f', 'raw',
    ].contains(lowerFormat);
  }
  
  @override
  String get name => 'RAW Processor';
  
  @override
  bool get isAvailable => true;
  
  /// Get the last error message
  String _getLastError() {
    final errorPtr = _bindings!.raw_processor_get_error();
    return fromCString(errorPtr) ?? 'Unknown error';
  }
  
  /// Get the bindings instance
  static LibRawBindings get bindings {
    if (_bindings == null) {
      initialize();
    }
    return _bindings!;
  }
}