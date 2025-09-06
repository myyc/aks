import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import '../ffi/libraw_bindings.dart';
import 'image_processor.dart' as img_proc;

class RawProcessor {
  static late LibRawBindings _bindings;
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    
    // Try loading from relative path first (when running from build directory)
    final List<String> libraryPaths;
    if (Platform.isLinux) {
      libraryPaths = [
        'linux/libraw_processor.so', 
        'lib/libraw_processor.so', 
        'libraw_processor.so', 
        './libraw_processor.so'
      ];
    } else if (Platform.isMacOS) {
      // When running with flutter run, the working directory is the project root
      // When running as an app bundle, libraries are in Frameworks/
      libraryPaths = [
        'build/macos/Build/Products/Debug/libraw_processor.dylib',
        'build/macos/Build/Products/Release/libraw_processor.dylib',
        'macos/libraw_processor.dylib',
        'libraw_processor.dylib',
        './libraw_processor.dylib',
        '@executable_path/../Frameworks/libraw_processor.dylib',  // App bundle
        '../Frameworks/libraw_processor.dylib',  // Release build location
        '../Resources/libraw_processor.dylib',   // Alternative bundle location
      ];
    } else {
      throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
    }
    
    for (final path in libraryPaths) {
      try {
        final dylib = DynamicLibrary.open(path);
        _bindings = LibRawBindings(dylib);
        _initialized = true;
        print('Successfully loaded libraw_processor from: $path');
        return;
      } catch (e) {
        print('Failed to load from $path: $e');
      }
    }
    
    throw Exception('Failed to load libraw_processor from any path. Tried: ${libraryPaths.join(", ")}');
  }

  static Future<img_proc.RawPixelData?> loadRawFile(String filePath) async {
    if (!_initialized) {
      initialize();
    }

    // Check if file exists and has RAW extension
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File not found: $filePath');
    }

    final extension = filePath.split('.').last.toLowerCase();
    const rawExtensions = [
      'cr2', 'cr3', 'nef', 'arw', 'orf', 'dng', 'raf', 'rw2',
      'pef', 'srw', 'x3f', 'erf', 'mef', 'mrw', 'nrw', 'rwl',
      'iiq', '3fr', 'dcr', 'kdc', 'sr2', 'srf', 'mdc', 'raw'
    ];

    if (!rawExtensions.contains(extension)) {
      throw Exception('Not a RAW file: $filePath');
    }

    // Process in isolate to avoid blocking UI
    return await _processInBackground(filePath);
  }

  static Future<img_proc.RawPixelData?> _processInBackground(String filePath) async {
    Pointer<Void> processor = nullptr;
    Pointer<RawImageData> imageData = nullptr;

    try {
      // Initialize processor
      processor = _bindings.raw_processor_init();
      if (processor == nullptr) {
        final error = _bindings.raw_processor_get_error().cast<Utf8>().toDartString();
        throw Exception('Failed to initialize processor: $error');
      }

      // Open and unpack RAW file
      final pathPtr = filePath.toNativeUtf8();
      final result = _bindings.raw_processor_open(processor, pathPtr.cast<Char>());
      calloc.free(pathPtr);

      if (result != 0) {
        final error = _bindings.raw_processor_get_error().cast<Utf8>().toDartString();
        throw Exception('Failed to open RAW file: $error');
      }

      // Process the image
      final processResult = _bindings.raw_processor_process(processor);
      if (processResult != 0) {
        final error = _bindings.raw_processor_get_error().cast<Utf8>().toDartString();
        throw Exception('Failed to process RAW: $error');
      }

      // Get RGB data
      imageData = _bindings.raw_processor_get_rgb(processor);
      if (imageData == nullptr) {
        final error = _bindings.raw_processor_get_error().cast<Utf8>().toDartString();
        throw Exception('Failed to get RGB data: $error');
      }

      // Convert to Flutter image
      final data = imageData.ref;
      final width = data.info.width;
      final height = data.info.height;
      final colors = data.info.colors;
      final dataSize = data.size;

      // Copy RGB data to Dart
      final pixels = Uint8List(dataSize);
      for (int i = 0; i < dataSize; i++) {
        pixels[i] = data.data[i];
      }

      // Convert to RGB if needed (handle grayscale)
      final rgbPixels = colors == 3 ? pixels : _convertGrayToRGB(pixels, width, height);
      
      // Return raw image data for processing
      return img_proc.RawPixelData(
        pixels: rgbPixels,
        width: width,
        height: height,
      );

    } catch (e) {
      print('Error processing RAW file: $e');
      rethrow;
    } finally {
      // Cleanup
      if (imageData != nullptr) {
        _bindings.raw_processor_free_image(imageData);
      }
      if (processor != nullptr) {
        _bindings.raw_processor_cleanup(processor);
      }
    }
  }

  static Uint8List _convertGrayToRGB(Uint8List gray, int width, int height) {
    final rgbSize = width * height * 3;
    final rgb = Uint8List(rgbSize);
    
    int grayIndex = 0;
    int rgbIndex = 0;
    for (int i = 0; i < width * height; i++) {
      final value = gray[grayIndex++];
      rgb[rgbIndex++] = value; // R
      rgb[rgbIndex++] = value; // G
      rgb[rgbIndex++] = value; // B
    }
    
    return rgb;
  }
}